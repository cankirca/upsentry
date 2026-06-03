#!/bin/bash
#
# upsentry-sessions.sh -- best-effort warning to terminal sessions.
# Runs AS the session user (invoked via sudo -u from upsentry-notify.sh).
#
# Types a "save your state" message ONLY into tmux/byobu panes whose
# foreground process (or its process tree) matches UPSENTRY_PATTERN —
# typically an AI coding agent such as Claude Code.  Panes that do not
# match are never touched: no keystrokes are ever injected into editors,
# shells or REPLs.
#
# Inputs (environment):
#   UPSENTRY_PATTERN   case-insensitive substring to match (default: claude)
#   UPSENTRY_MESSAGE   text to type, followed by Enter
#   UPSENTRY_LOG       log file (must be writable by this user)
#
# Part of UPSentry — https://github.com/cankirca/upsentry

PATTERN="${UPSENTRY_PATTERN:-claude}"
MSG="${UPSENTRY_MESSAGE:-Power outage! Running on UPS battery. Please save your current progress now.}"
LOG="${UPSENTRY_LOG:-/var/log/upsentry.log}"
NOW="$(date '+%d.%m.%Y %H:%M:%S')"

log() {
    printf '%s | sessions | %s\n' "$NOW" "$1" >> "$LOG" 2>/dev/null
}

command -v tmux >/dev/null 2>&1 || { log "tmux not installed; nothing to do"; exit 0; }

PANES="$(tmux list-panes -a \
    -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_pid}' \
    2>/dev/null)"

if [ -z "$PANES" ]; then
    log "no tmux server / no panes; nothing to do"
    exit 0
fi

# True if the pane's process tree (pid + descendants) matches PATTERN.
proc_tree_matches() {
    local pid="$1"
    [ -z "$pid" ] && return 1
    local pids="$pid" frontier="$pid" depth=0
    while [ -n "$frontier" ] && [ "$depth" -lt 10 ]; do
        local children=""
        for p in $frontier; do
            local c
            c="$(pgrep -P "$p" 2>/dev/null)"
            [ -n "$c" ] && children="$children $c"
        done
        children="$(echo $children)"
        [ -z "$children" ] && break
        pids="$pids $children"
        frontier="$children"
        depth=$((depth + 1))
    done
    for p in $pids; do
        if ps -p "$p" -o args= 2>/dev/null | grep -qi -- "$PATTERN"; then
            return 0
        fi
    done
    return 1
}

matched=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    pane="$(printf '%s' "$line" | awk '{print $1}')"
    fgcmd="$(printf '%s' "$line" | awk '{print $2}')"
    panepid="$(printf '%s' "$line" | awk '{print $3}')"

    is_match=0
    if printf '%s' "$fgcmd" | grep -qi -- "$PATTERN"; then
        is_match=1
    elif proc_tree_matches "$panepid"; then
        is_match=1
    fi

    if [ "$is_match" -eq 1 ]; then
        if tmux send-keys -t "$pane" "$MSG" Enter 2>/dev/null; then
            log "MATCH pane=${pane} fg=${fgcmd} pid=${panepid} -> message sent"
            matched=$((matched + 1))
        else
            log "MATCH pane=${pane} fg=${fgcmd} pid=${panepid} -> send-keys FAILED"
        fi
    else
        log "SKIP  pane=${pane} fg=${fgcmd} pid=${panepid} -> no '${PATTERN}' process"
    fi
done <<EOF
$PANES
EOF

log "done; ${matched} session(s) notified"
exit 0
