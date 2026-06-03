#!/bin/bash
#
# UPSentry installer
# ------------------
# Sets up a NUT netclient that watches your UPS through any NUT master
# (NAS or server) and wires up notifications + clean shutdown.
#
# Interactive:      sudo ./install.sh
# Non-interactive:  sudo ./install.sh --yes --ups-name ups --nut-host 192.168.1.50 \
#                       --nut-user upsmon --nut-password secret --notifiers telegram \
#                       --telegram-token 123:abc --telegram-chat 4567
#
# Part of UPSentry — https://github.com/cankirca/upsentry

set -u

# ---------- defaults ----------
UPS_NAME="" NUT_HOST="" NUT_USER="" NUT_PASSWORD=""
NOTIFIERS=""
NETGSM_USERCODE="" NETGSM_PASSWORD="" NETGSM_HEADER="" NETGSM_GSMNO=""
TELEGRAM_BOT_TOKEN="" TELEGRAM_CHAT_ID=""
WEBHOOK_URL=""
SESSION_NOTIFY_ENABLED="no" SESSION_USER="" SESSION_PROCESS_PATTERN="claude"
ASSUME_YES=0

INSTALL_DIR="/opt/upsentry"
CONFIG_DIR="/etc/upsentry"
CONFIG="$CONFIG_DIR/upsentry.conf"
LOG_FILE="/var/log/upsentry.log"
STATE_DIR="/var/lib/upsentry"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- helpers ----------
c_info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[1;32m ✓ \033[0m %s\n' "$*"; }
c_warn()  { printf '\033[1;33m ! \033[0m %s\n' "$*"; }
c_err()   { printf '\033[1;31m ✗ \033[0m %s\n' "$*" >&2; }
die()     { c_err "$*"; exit 1; }

ask() { # ask <prompt> <varname> [default] [secret]
    local prompt="$1" var="$2" def="${3:-}" secret="${4:-}" val flag
    if [ "$ASSUME_YES" -eq 1 ]; then
        flag="${var,,}"; flag="--${flag//_/-}"
        [ -n "${!var}" ] || [ -n "$def" ] || die "--yes given but $flag missing"
        [ -n "${!var}" ] || printf -v "$var" '%s' "$def"
        return
    fi
    [ -n "${!var}" ] && return   # already provided via flag
    while :; do
        if [ -n "$secret" ]; then
            read -r -s -p "$prompt${def:+ [$def]}: " val </dev/tty; echo
        else
            read -r -p "$prompt${def:+ [$def]}: " val </dev/tty
        fi
        val="${val:-$def}"
        [ -n "$val" ] && { printf -v "$var" '%s' "$val"; return; }
        echo "  (required)"
    done
}

# ---------- parse flags ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --ups-name)         UPS_NAME="$2"; shift 2 ;;
        --nut-host)         NUT_HOST="$2"; shift 2 ;;
        --nut-user)         NUT_USER="$2"; shift 2 ;;
        --nut-password)     NUT_PASSWORD="$2"; shift 2 ;;
        --notifiers)        NOTIFIERS="$2"; shift 2 ;;
        --netgsm-usercode)  NETGSM_USERCODE="$2"; shift 2 ;;
        --netgsm-password)  NETGSM_PASSWORD="$2"; shift 2 ;;
        --netgsm-header)    NETGSM_HEADER="$2"; shift 2 ;;
        --netgsm-gsmno)     NETGSM_GSMNO="$2"; shift 2 ;;
        --telegram-token)   TELEGRAM_BOT_TOKEN="$2"; shift 2 ;;
        --telegram-chat)    TELEGRAM_CHAT_ID="$2"; shift 2 ;;
        --webhook-url)      WEBHOOK_URL="$2"; shift 2 ;;
        --session-user)     SESSION_USER="$2"; SESSION_NOTIFY_ENABLED="yes"; shift 2 ;;
        --session-pattern)  SESSION_PROCESS_PATTERN="$2"; shift 2 ;;
        --yes|-y)           ASSUME_YES=1; shift ;;
        --help|-h)
            sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

# ---------- preflight ----------
[ "$(id -u)" -eq 0 ] || die "run as root:  sudo ./install.sh"
command -v systemctl >/dev/null || die "systemd is required"

echo
echo "  ╦ ╦╔═╗╔═╗┌─┐┌┐┌┌┬┐┬─┐┬ ┬"
echo "  ║ ║╠═╝╚═╗├┤ │││ │ ├┬┘└┬┘"
echo "  ╚═╝╩  ╚═╝└─┘┘└┘ ┴ ┴└─ ┴   power-outage watchdog"
echo

# ---------- gather answers ----------
c_info "UPS / NUT master connection"
ask "UPS name (as defined on the NUT master)" UPS_NAME "ups"
ask "NUT master host/IP (your NAS or server)" NUT_HOST
ask "NUT username" NUT_USER "upsmon"
ask "NUT password" NUT_PASSWORD "" secret

if [ -z "$NOTIFIERS" ] && [ "$ASSUME_YES" -eq 0 ]; then
    echo
    c_info "Notification channels (space separated): netgsm telegram webhook (or 'none')"
    read -r -p "Notifiers [none]: " NOTIFIERS </dev/tty
fi
NOTIFIERS="${NOTIFIERS:-}"
NOTIFIERS="${NOTIFIERS//,/ }"          # accept commas too
[ "$NOTIFIERS" = "none" ] && NOTIFIERS=""
for n in $NOTIFIERS; do
    case "$n" in netgsm|telegram|webhook) ;;
        *) die "unknown notifier '$n' (available: netgsm telegram webhook)" ;;
    esac
done

case " $NOTIFIERS " in *" netgsm "*)
    c_info "NetGSM SMS settings"
    ask "NetGSM usercode (subscriber number)" NETGSM_USERCODE
    ask "NetGSM password" NETGSM_PASSWORD "" secret
    ask "NetGSM approved sender title (msgheader)" NETGSM_HEADER
    ask "Recipient GSM number (5xxxxxxxxx)" NETGSM_GSMNO
esac
case " $NOTIFIERS " in *" telegram "*)
    c_info "Telegram bot settings"
    ask "Telegram bot token" TELEGRAM_BOT_TOKEN "" secret
    ask "Telegram chat id" TELEGRAM_CHAT_ID
esac
case " $NOTIFIERS " in *" webhook "*)
    c_info "Webhook settings"
    ask "Webhook URL (e.g. https://ntfy.sh/your-topic)" WEBHOOK_URL
esac

if [ "$ASSUME_YES" -eq 0 ] && [ -z "$SESSION_USER" ]; then
    echo
    read -r -p "Warn AI/tmux sessions on power loss? (username, empty = skip): " SESSION_USER </dev/tty
    [ -n "$SESSION_USER" ] && SESSION_NOTIFY_ENABLED="yes"
fi
if [ -n "$SESSION_USER" ] && ! id "$SESSION_USER" >/dev/null 2>&1; then
    die "user '$SESSION_USER' does not exist"
fi

# ---------- install packages ----------
echo
c_info "Installing packages (nut-client, curl)"
if command -v apt-get >/dev/null; then
    apt-get update -qq && apt-get install -y -qq nut-client curl >/dev/null \
        || die "package installation failed"
else
    command -v upsmon >/dev/null || die "apt not found — install NUT client tools manually, then re-run"
fi
c_ok "packages ready"

# ---------- copy program files ----------
c_info "Installing UPSentry to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r "$SRC_DIR/bin" "$SRC_DIR/notifiers" "$INSTALL_DIR/"
chmod 750 "$INSTALL_DIR"/bin/* "$INSTALL_DIR"/notifiers/*
chmod 755 "$INSTALL_DIR/bin/upsentry"
ln -sf "$INSTALL_DIR/bin/upsentry" /usr/local/bin/upsentry
c_ok "program files installed"

# ---------- write config ----------
c_info "Writing $CONFIG"
mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG" ] && cp "$CONFIG" "$CONFIG.bak.$(date +%s)" && c_warn "existing config backed up"
cat > "$CONFIG" <<EOF
# UPSentry configuration — generated by install.sh on $(date '+%Y-%m-%d %H:%M')
# Reference for every option: upsentry.conf.example in the repo.

UPS_NAME="$UPS_NAME"
NUT_HOST="$NUT_HOST"
NUT_USER="$NUT_USER"
NUT_PASSWORD="$NUT_PASSWORD"

NOTIFIERS="$NOTIFIERS"

NETGSM_USERCODE="$NETGSM_USERCODE"
NETGSM_PASSWORD="$NETGSM_PASSWORD"
NETGSM_HEADER="$NETGSM_HEADER"
NETGSM_GSMNO="$NETGSM_GSMNO"
NETGSM_DIL="TR"
NETGSM_FILTER="0"

TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"

WEBHOOK_URL="$WEBHOOK_URL"
WEBHOOK_CONTENT_TYPE="text/plain"

MSG_ONBATT="Power outage started: {date}"
MSG_ONLINE="Power restored: {date} (outage lasted {duration})"
MSG_LOWBATT="UPS battery LOW — systems will shut down soon ({date})"
MSG_FSD="UPS critical — shutting down now ({date})"
DATE_FORMAT="%d.%m.%Y %H:%M:%S"

SESSION_NOTIFY_ENABLED="$SESSION_NOTIFY_ENABLED"
SESSION_USER="$SESSION_USER"
SESSION_PROCESS_PATTERN="$SESSION_PROCESS_PATTERN"
SESSION_MESSAGE="Power outage! Running on UPS battery. Please save your current progress now."

SNAPSHOT_TMUX="yes"

LOG_FILE="$LOG_FILE"
STATE_DIR="$STATE_DIR"
EOF
chmod 600 "$CONFIG"
c_ok "config written (mode 600 — credentials stay private)"

# ---------- NUT client configuration ----------
c_info "Configuring NUT (netclient mode)"
[ -f /etc/nut/nut.conf ] && cp /etc/nut/nut.conf "/etc/nut/nut.conf.bak.upsentry" 2>/dev/null
sed -i 's/^MODE=.*/MODE=netclient/' /etc/nut/nut.conf 2>/dev/null \
    || echo "MODE=netclient" >> /etc/nut/nut.conf

[ -f /etc/nut/upsmon.conf ] && cp /etc/nut/upsmon.conf "/etc/nut/upsmon.conf.bak.upsentry"
cat > /etc/nut/upsmon.conf <<EOF
# Generated by UPSentry install.sh — backup of the previous file:
# /etc/nut/upsmon.conf.bak.upsentry

MONITOR ${UPS_NAME}@${NUT_HOST} 1 ${NUT_USER} ${NUT_PASSWORD} slave

MINSUPPLIES 1

SHUTDOWNCMD "$INSTALL_DIR/bin/upsentry-shutdown.sh"
NOTIFYCMD "$INSTALL_DIR/bin/upsentry-notify.sh"

NOTIFYFLAG ONLINE  SYSLOG+EXEC
NOTIFYFLAG ONBATT  SYSLOG+EXEC
NOTIFYFLAG LOWBATT SYSLOG+EXEC
NOTIFYFLAG FSD     SYSLOG+EXEC
NOTIFYFLAG COMMBAD SYSLOG
NOTIFYFLAG COMMOK  SYSLOG
NOTIFYFLAG SHUTDOWN SYSLOG

POLLFREQ 5
POLLFREQALERT 5
DEADTIME 15
EOF
chown root:nut /etc/nut/upsmon.conf 2>/dev/null
chmod 640 /etc/nut/upsmon.conf
c_ok "NUT client configured"

# upsmon normally drops NOTIFYCMD to the unprivileged 'nut' user, which
# cannot sudo to the session user.  Run upsmon privileged (-p) instead;
# config files stay root-only so credentials remain protected.
c_info "Installing systemd drop-in (upsmon -p)"
mkdir -p /etc/systemd/system/nut-monitor.service.d
cat > /etc/systemd/system/nut-monitor.service.d/upsentry.conf <<'EOF'
[Service]
# UPSentry: run upsmon privileged so NOTIFYCMD can read the root-only
# config and switch to the session user for tmux warnings.
ExecStart=
ExecStart=/sbin/upsmon -F -p
EOF
systemctl daemon-reload
c_ok "drop-in installed"

# ---------- log + state ----------
touch "$LOG_FILE"
mkdir -p "$STATE_DIR"
if [ -n "$SESSION_USER" ]; then
    chown "root:$SESSION_USER" "$LOG_FILE"
    chmod 660 "$LOG_FILE"   # session warnings are logged by that user
else
    chmod 640 "$LOG_FILE"
fi
c_ok "log: $LOG_FILE   state: $STATE_DIR"

# ---------- start + verify ----------
c_info "Starting nut-monitor"
systemctl enable nut-monitor >/dev/null 2>&1
systemctl restart nut-monitor
sleep 3
if systemctl is-active nut-monitor >/dev/null; then
    c_ok "nut-monitor is running"
else
    c_err "nut-monitor failed to start — check: journalctl -u nut-monitor"
fi

c_info "Testing connection to ${UPS_NAME}@${NUT_HOST}"
if STATUS="$(timeout 8 upsc "${UPS_NAME}@${NUT_HOST}" ups.status 2>/dev/null)"; then
    CHARGE="$(timeout 8 upsc "${UPS_NAME}@${NUT_HOST}" battery.charge 2>/dev/null)"
    c_ok "connected — ups.status=${STATUS} battery.charge=${CHARGE:-?}%"
else
    c_warn "could not query the UPS yet. Checklist:"
    echo "      - is upsd on ${NUT_HOST} listening on the LAN? (LISTEN 0.0.0.0 3493)"
    echo "      - is this machine's IP allowed on the master?"
    echo "      - note: many NAS devices block ping — that does NOT mean NUT is down"
fi

echo
echo "──────────────────────────────────────────────────────"
c_ok "UPSentry installed!"
echo
echo "   try it:"
echo "     upsentry status                  # live UPS readings"
echo "     sudo upsentry test onbatt        # send a REAL test notification"
echo "     sudo upsentry simulate-shutdown  # dry-run the shutdown hook"
echo "     upsentry stats                   # outage history"
echo
echo "   config:  $CONFIG"
echo "   log:     $LOG_FILE"
echo "──────────────────────────────────────────────────────"
