#!/bin/bash
#
# webhook.sh -- UPSentry notifier: POST the message to any webhook URL.
#
# Works out of the box with ntfy.sh, and with anything that accepts a
# plain-text or JSON body (Slack/Discord via their webhook URLs, Home
# Assistant webhooks, Gotify, ...).
#
#   ntfy:    WEBHOOK_URL="https://ntfy.sh/your-topic"
#   Slack:   WEBHOOK_URL="https://hooks.slack.com/services/..." and
#            WEBHOOK_CONTENT_TYPE="application/json" (body becomes {"text": ...})
#
# Usage: webhook.sh "message text"
#
# Part of UPSentry — https://github.com/cankirca/upsentry

CONFIG="${UPSENTRY_CONFIG:-/etc/upsentry/upsentry.conf}"
[ -r "$CONFIG" ] || { echo "webhook: config not readable"; exit 1; }
# shellcheck source=/dev/null
. "$CONFIG"

MESSAGE="$1"
[ -n "$MESSAGE" ] || { echo "webhook: empty message"; exit 1; }
[ -n "$WEBHOOK_URL" ] || { echo "webhook: WEBHOOK_URL not set"; exit 1; }

CT="${WEBHOOK_CONTENT_TYPE:-text/plain}"

if [ "$CT" = "application/json" ]; then
    # Minimal JSON escaping for the message body.
    ESC="$(printf '%s' "$MESSAGE" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    BODY="{\"text\": \"${ESC}\"}"
else
    BODY="$MESSAGE"
fi

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
    -H "Content-Type: ${CT}" \
    -X POST --data "$BODY" "$WEBHOOK_URL" 2>/dev/null)"
RC=$?

[ $RC -eq 0 ] || { echo "webhook: curl failed rc=$RC"; exit 1; }

case "$HTTP_CODE" in
    2*) echo "webhook: http=${HTTP_CODE}"; exit 0 ;;
    *)  echo "webhook: http=${HTTP_CODE}"; exit 1 ;;
esac
