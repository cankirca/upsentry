# Contributing to UPSentry

Thanks for your interest! UPSentry is intentionally small and dependency-free
(pure bash + curl), and contributions that keep it that way are very welcome.

## Easy wins

- **New notifiers** — a notifier is a single executable script in `notifiers/`
  that takes the message as `$1`, prints one result line and exits 0/1.
  See `notifiers/webhook.sh` for the simplest example.
- **Translations** — message presets for more languages.
- **Roadmap items** — check the open issues for planned features.

## Ground rules

1. **Pure bash** (no python/node runtime dependencies), `curl` is allowed.
2. **ShellCheck-clean** — CI runs `shellcheck -S warning` on every script.
3. **Never block the event pipeline** — a failing notifier/hook must be
   logged and skipped, not crash `upsmon`'s NOTIFYCMD.
4. **No secrets in code** — credentials only ever live in
   `/etc/upsentry/upsentry.conf` (root-only).
5. **Safety first for tmux injection** — anything that types into a pane
   must pattern-match the pane's process tree first and log every decision.

## Dev loop

```bash
# point the scripts at a sandbox config — no root, no real notifications
mkdir -p /tmp/dev && cat > /tmp/dev/conf <<'EOF'
NOTIFIERS=""
LOG_FILE="/tmp/dev/log"
STATE_DIR="/tmp/dev/state"
EOF
export UPSENTRY_CONFIG=/tmp/dev/conf
NOTIFYTYPE=ONBATT ./bin/upsentry-notify.sh && cat /tmp/dev/log

# lint before pushing
shellcheck -S warning install.sh uninstall.sh bin/* notifiers/*.sh
```

## Pull requests

- One feature/fix per PR, with a short description of *why*.
- Update `README.md` and `upsentry.conf.example` if you add config options.
- Add a line to `CHANGELOG.md` under *Unreleased*.
