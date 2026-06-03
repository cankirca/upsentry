#!/bin/bash
#
# UPSentry uninstaller — removes UPSentry and restores backed-up NUT configs.
# Usage: sudo ./uninstall.sh
#
# Part of UPSentry — https://github.com/cankirca/upsentry

set -u
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo ./uninstall.sh" >&2; exit 1; }

echo "This removes /opt/upsentry, the systemd drop-in and the CLI symlink."
read -r -p "Continue? [y/N] " ans </dev/tty
[ "${ans,,}" = "y" ] || { echo "aborted"; exit 0; }

rm -rf /opt/upsentry
rm -f /usr/local/bin/upsentry
rm -f /etc/systemd/system/nut-monitor.service.d/upsentry.conf
rmdir /etc/systemd/system/nut-monitor.service.d 2>/dev/null

# Restore NUT configs if we backed them up.
for f in /etc/nut/upsmon.conf /etc/nut/nut.conf; do
    [ -f "$f.bak.upsentry" ] && mv "$f.bak.upsentry" "$f" && echo "restored $f"
done

systemctl daemon-reload
systemctl restart nut-monitor 2>/dev/null

read -r -p "Also delete config + logs + outage history? [y/N] " ans </dev/tty
if [ "${ans,,}" = "y" ]; then
    rm -rf /etc/upsentry /var/lib/upsentry
    rm -f /var/log/upsentry.log
    echo "config and data removed"
else
    echo "kept: /etc/upsentry, /var/lib/upsentry, /var/log/upsentry.log"
fi

echo "UPSentry uninstalled."
