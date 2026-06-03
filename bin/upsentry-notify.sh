#!/bin/bash
#
# upsentry-notify.sh -- NUT NOTIFYCMD hook.
# Invoked by upsmon with NOTIFYTYPE set (ONBATT, ONLINE, LOWBATT, FSD, ...).
# Builds the event message, records outage history, dispatches it to every
# configured notifier, and (on ONBATT) warns matching tmux sessions.
#
# Part of UPSentry — https://github.com/cankirca/upsentry

CONFIG="${UPSENTRY_CONFIG:-/etc/upsentry/upsentry.conf}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -r "$CONFIG" ] || exit 0
# shellcheck source=/dev/null
. "$CONFIG"

LOG_FILE="${LOG_FILE:-/var/log/upsentry.log}"
STATE_DIR="${STATE_DIR:-/var/lib/upsentry}"
DATE_FORMAT="${DATE_FORMAT:-%d.%m.%Y %H:%M:%S}"

EVENT="${NOTIFYTYPE:-UNKNOWN}"
NOW="$(date +"$DATE_FORMAT")"
EPOCH="$(date +%s)"

log() {
    printf '%s | event=%s | %s\n' "$NOW" "$EVENT" "$1" >> "$LOG_FILE" 2>/dev/null
}

human_duration() {
    local s=$1 out=""
    [ "$s" -ge 3600 ] && { out="$((s / 3600))h "; s=$((s % 3600)); }
    [ "$s" -ge 60 ]   && { out="${out}$((s / 60))m "; s=$((s % 60)); }
    printf '%s%ss' "$out" "$s"
}

mkdir -p "$STATE_DIR" 2>/dev/null

# Default message templates (kept in plain variables: putting "{date}" inside
# a ${VAR:-default} expansion trips bash's brace matching).
DEF_ONBATT='Power outage started: {date}'
DEF_ONLINE='Power restored: {date} (outage lasted {duration})'
DEF_LOWBATT='UPS battery LOW: {date}'
DEF_FSD='UPS critical, shutting down: {date}'

DURATION=""
DURATION_SECS=""
case "$EVENT" in
    ONBATT)
        echo "$EPOCH" > "$STATE_DIR/onbatt.ts" 2>/dev/null
        MSG="${MSG_ONBATT:-$DEF_ONBATT}"
        ;;
    ONLINE)
        if [ -f "$STATE_DIR/onbatt.ts" ]; then
            START="$(cat "$STATE_DIR/onbatt.ts" 2>/dev/null)"
            if [ -n "$START" ] && [ "$EPOCH" -ge "$START" ]; then
                DURATION_SECS=$((EPOCH - START))
                DURATION="$(human_duration "$DURATION_SECS")"
            fi
            rm -f "$STATE_DIR/onbatt.ts"
        fi
        MSG="${MSG_ONLINE:-$DEF_ONLINE}"
        ;;
    LOWBATT)
        MSG="${MSG_LOWBATT:-$DEF_LOWBATT}"
        ;;
    FSD|SHUTDOWN)
        MSG="${MSG_FSD:-$DEF_FSD}"
        ;;
    *)
        # COMMBAD, COMMOK, REPLBATT, NOCOMM ... -> log only.
        log "no notification configured for this event"
        exit 0
        ;;
esac

# Fill placeholders.
DUR_TEXT="${DURATION:-unknown}"
UPS_TEXT="${UPSNAME:-${UPS_NAME:-ups}}"
MSG="${MSG//'{date}'/$NOW}"
MSG="${MSG//'{duration}'/$DUR_TEXT}"
MSG="${MSG//'{ups}'/$UPS_TEXT}"

# Outage history (CSV: iso-date,event,duration_seconds).
printf '%s,%s,%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$EVENT" "$DURATION_SECS" \
    >> "$STATE_DIR/events.csv" 2>/dev/null

# Dispatch to notifiers.  A failing notifier never blocks the others.
SENT=0
for n in ${NOTIFIERS//,/ }; do
    script="$LIB_DIR/notifiers/${n}.sh"
    if [ -x "$script" ]; then
        if RESULT="$("$script" "$MSG" 2>&1)"; then
            log "notifier=${n} ok ${RESULT} | msg=${MSG}"
            SENT=$((SENT + 1))
        else
            log "notifier=${n} FAILED ${RESULT} | msg=${MSG}"
        fi
    else
        log "notifier=${n} not found at ${script}"
    fi
done
[ -z "${NOTIFIERS// /}" ] && log "no notifiers configured | msg=${MSG}"

# ONBATT only: best-effort warning to matching tmux sessions.
# Runs as SESSION_USER; config values are passed via env so the
# credential-holding config never needs to be readable by that user.
if [ "$EVENT" = "ONBATT" ] && [ "${SESSION_NOTIFY_ENABLED:-no}" = "yes" ] && [ -n "$SESSION_USER" ]; then
    if [ -x "$LIB_DIR/bin/upsentry-sessions.sh" ]; then
        sudo -u "$SESSION_USER" env \
            UPSENTRY_PATTERN="${SESSION_PROCESS_PATTERN:-claude}" \
            UPSENTRY_MESSAGE="${SESSION_MESSAGE:-Power outage! Please save your work.}" \
            UPSENTRY_LOG="$LOG_FILE" \
            "$LIB_DIR/bin/upsentry-sessions.sh" >/dev/null 2>&1 \
            || log "session notify returned non-zero (ignored)"
    fi
fi

exit 0
