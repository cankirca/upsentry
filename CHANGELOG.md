# Changelog

## 1.0.0 — 2026-06-03

First public release. 🎉

- NUT netclient setup with interactive + non-interactive installer
- Event hooks for `ONBATT`, `ONLINE`, `LOWBATT`, `FSD`
- Notifiers: NetGSM SMS, Telegram, generic webhook (ntfy/Slack/Discord/…)
- Outage history + `upsentry stats` (count, total/average/longest downtime)
- AI/tmux session warning on power loss (pattern-matched panes only)
- Graceful shutdown with tmux-resurrect / window-map snapshot
- `upsentry` CLI: `status`, `test`, `log`, `stats`, `simulate-shutdown`
- Message templates with `{date}`, `{duration}`, `{ups}` placeholders
- Uninstaller restoring original NUT configs
