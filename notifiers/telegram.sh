#!/bin/bash
#
# telegram.sh -- UPSentry notifier: message via a Telegram bot.
#
# Setup: create a bot with @BotFather, get its token, then send the bot a
# message and read your chat id from
#   https://api.telegram.org/bot<TOKEN>/getUpdates
#
# Usage: telegram.sh "message text"
#
# Part of UPSentry — https://github.com/cankirca/upsentry

CONFIG="${UPSENTRY_CONFIG:-/etc/upsentry/upsentry.conf}"
[ -r "$CONFIG" ] || { echo "telegram: config not readable"; exit 1; }
# shellcheck source=/dev/null
. "$CONFIG"

MESSAGE="$1"
[ -n "$MESSAGE" ] || { echo "telegram: empty message"; exit 1; }
[ -n "$TELEGRAM_BOT_TOKEN" ] || { echo "telegram: TELEGRAM_BOT_TOKEN not set"; exit 1; }
[ -n "$TELEGRAM_CHAT_ID" ]  || { echo "telegram: TELEGRAM_CHAT_ID not set"; exit 1; }

RESPONSE="$(curl -s --max-time 20 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MESSAGE}" 2>/dev/null)"
RC=$?

[ $RC -eq 0 ] || { echo "telegram: curl failed rc=$RC"; exit 1; }

if printf '%s' "$RESPONSE" | grep -q '"ok":true'; then
    echo "telegram: ok"
    exit 0
fi
echo "telegram: API error: $(printf '%.120s' "$RESPONSE")"
exit 1
