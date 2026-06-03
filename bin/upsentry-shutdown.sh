#!/bin/bash
#
# upsentry-shutdown.sh -- NUT SHUTDOWNCMD hook.
# Runs (as root) when the NUT master orders a shutdown (battery low / FSD).
# Optionally snapshots the tmux session layout of SESSION_USER, syncs disks
# and halts the machine cleanly.
#
# Dry run:  UPSENTRY_DRY_RUN=1 upsentry-shutdown.sh   (or: upsentry simulate-shutdown)
#
# Part of UPSentry — https://github.com/cankirca/upsentry

CONFIG="${UPSENTRY_CONFIG:-/etc/upsentry/upsentry.conf}"
# shellcheck source=/dev/null
[ -r "$CONFIG" ] && . "$CONFIG"

LOG_FILE="${LOG_FILE:-/var/log/upsentry.log}"
NOW="$(date '+%d.%m.%Y %H:%M:%S')"
STAMP="$(date '+%Y%m%d-%H%M%S')"
DRY="${UPSENTRY_DRY_RUN:-0}"

log() {
    printf '%s | shutdown | %s\n' "$NOW" "$1" >> "$LOG_FILE" 2>/dev/null
    [ "$DRY" = "1" ] && echo "[dry-run] $1"
}

log "SHUTDOWNCMD invoked (dry_run=${DRY})"

# --- Save tmux session map (best effort, never blocks shutdown) ---
if [ "${SNAPSHOT_TMUX:-no}" = "yes" ] && [ -n "$SESSION_USER" ]; then
    USER_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
    RESURRECT="${USER_HOME}/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    SNAPSHOT="${USER_HOME}/upsentry-snapshot-${STAMP}.txt"

    # shellcheck disable=SC2024  # script runs as root: root performs the redirect deliberately
    if [ -x "$RESURRECT" ]; then
        if sudo -u "$SESSION_USER" tmux run-shell "$RESURRECT" >/dev/null 2>&1; then
            log "tmux-resurrect snapshot saved"
        else
            log "tmux-resurrect save failed (continuing)"
        fi
    elif sudo -u "$SESSION_USER" tmux list-windows -a \
            -F '#{session_name}:#{window_index} [#{window_name}] #{pane_current_path} -> #{pane_current_command}' \
            > "$SNAPSHOT" 2>/dev/null; then
        chown "${SESSION_USER}:" "$SNAPSHOT" 2>/dev/null
        log "window/dir map dumped to ${SNAPSHOT}"
    else
        log "no tmux server / could not snapshot (continuing)"
    fi
fi

sync
sleep 2
log "filesystem synced"

if [ "$DRY" = "1" ]; then
    log "dry run complete — NOT shutting down"
    exit 0
fi

log "issuing clean shutdown (-h +0)"
/sbin/shutdown -h +0
exit 0
