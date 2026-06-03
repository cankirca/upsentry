#!/bin/bash
#
# netgsm.sh -- UPSentry notifier: SMS via the NetGSM HTTP GET API.
# https://www.netgsm.com.tr  (Turkish SMS provider)
#
# Usage: netgsm.sh "message text"
# Prints a short result line to stdout; exit 0 on success.
#
# Part of UPSentry — https://github.com/cankirca/upsentry

CONFIG="${UPSENTRY_CONFIG:-/etc/upsentry/upsentry.conf}"
[ -r "$CONFIG" ] || { echo "netgsm: config not readable"; exit 1; }
# shellcheck source=/dev/null
. "$CONFIG"

MESSAGE="$1"
[ -n "$MESSAGE" ] || { echo "netgsm: empty message"; exit 1; }

for v in NETGSM_USERCODE NETGSM_PASSWORD NETGSM_HEADER NETGSM_GSMNO; do
    [ -n "${!v}" ] || { echo "netgsm: $v is not set"; exit 1; }
done

ENDPOINT='https://api.netgsm.com.tr/sms/send/get'

RESPONSE="$(curl -s --get "$ENDPOINT" \
    --max-time 20 \
    --data-urlencode "usercode=${NETGSM_USERCODE}" \
    --data-urlencode "password=${NETGSM_PASSWORD}" \
    --data-urlencode "gsmno=${NETGSM_GSMNO}" \
    --data-urlencode "message=${MESSAGE}" \
    --data-urlencode "msgheader=${NETGSM_HEADER}" \
    --data-urlencode "dil=${NETGSM_DIL:-TR}" \
    --data-urlencode "filter=${NETGSM_FILTER:-0}" 2>/dev/null)"
RC=$?

[ $RC -eq 0 ] || { echo "netgsm: curl failed rc=$RC"; exit 1; }

# First whitespace-delimited token of the reply is the status code.
CODE="$(printf '%s' "$RESPONSE" | tr -s '[:space:]' ' ' | sed 's/^ *//' | cut -d' ' -f1)"

case "$CODE" in
    00) echo "netgsm: code=00 (queued for delivery)"; exit 0 ;;
    30) echo "netgsm: code=30 (bad credentials / API access / IP restriction)"; exit 1 ;;
    40) echo "netgsm: code=40 (sender title not approved)"; exit 1 ;;
    50) echo "netgsm: code=50 (recipient not in IYS consent list)"; exit 1 ;;
    60) echo "netgsm: code=60 (account inactive or no balance)"; exit 1 ;;
    70) echo "netgsm: code=70 (missing or invalid parameter)"; exit 1 ;;
    *)  echo "netgsm: code=${CODE:-none} (unexpected response)"; exit 1 ;;
esac
