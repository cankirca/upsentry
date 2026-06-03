# ⚡ UPSentry

> **The power just went out. Do you know?**
> UPSentry is a lightweight power-outage watchdog for Raspberry Pi and any Linux box. It watches your UPS over the network (via [NUT](https://networkupstools.org/)), texts you the moment the power dies — and the moment it comes back — warns your running AI coding sessions to save their work, keeps outage statistics for your home, and shuts the machine down cleanly before the battery runs dry.

[![CI](https://github.com/cankirca/upsentry/actions/workflows/ci.yml/badge.svg)](https://github.com/cankirca/upsentry/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%20%7C%20Debian%20%7C%20Ubuntu-c51a4a?logo=raspberrypi&logoColor=white)
![Shell](https://img.shields.io/badge/built%20with-pure%20bash-4EAA25?logo=gnubash&logoColor=white)
![NUT](https://img.shields.io/badge/works%20with-Network%20UPS%20Tools-blue)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Why?

A UPS keeps your gear alive during an outage — but it doesn't *tell* you anything. If you're away from home you find out hours later, your AI coding agent loses its unsaved context, and you have no record of how flaky your grid actually is.

UPSentry fills that gap with four small bash scripts and zero daemons of its own — it hooks straight into the battle-tested NUT event system you already have.

```
   Wall power ✕
        │
   ┌────▼─────┐  USB   ┌───────────────┐  LAN (NUT, port 3493)  ┌──────────────────┐
   │   UPS    ├───────►│  NUT master    ├───────────────────────►│  UPSentry         │
   │ (Eaton,  │        │ (NAS / server: │                        │  (Pi / any box)   │
   │  APC...) │        │  ASUSTOR,      │                        │   │               │
   └──────────┘        │  Synology,     │                        │   ├─📱 SMS        │
                       │  TrueNAS,      │                        │   ├─✈️ Telegram   │
                       │  Linux, ...)   │                        │   ├─🔔 Webhook    │
                       └────────────────┘                        │   ├─🤖 warn AI    │
                                                                 │   │   sessions    │
                                                                 │   ├─📊 stats      │
                                                                 │   └─🛑 clean      │
                                                                 │       shutdown    │
                                                                 └──────────────────┘
```

## ✨ Features

- 📱 **Instant alerts** on power loss, power restore, low battery and forced shutdown
  — measured **~4 seconds** from detection to SMS dispatch in real-world testing
- 🔌 **Pluggable notifiers** — ship with three, add your own in ~20 lines of bash:
  - **SMS** via [NetGSM](https://www.netgsm.com.tr) (a well-known Turkish SMS gateway)
  - **Telegram** bot messages
  - **Generic webhook** — works with [ntfy](https://ntfy.sh), Slack, Discord, Gotify, Home Assistant…
- ⏱️ **Outage analytics** — every event is recorded; `upsentry stats` shows how many
  outages you've had, total downtime, average and longest outage. Know your grid.
- 🤖 **AI-session protection** — on power loss, UPSentry types a "save your progress now"
  message into tmux/byobu panes running an AI coding agent (Claude Code, aider, …).
  Panes that don't match are **never** touched — no keystrokes into your editors or shells.
- 💾 **Graceful shutdown** — when the NUT master orders it: snapshot your tmux layout
  ([tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) if installed, plain
  window map otherwise), `sync`, halt.
- 🌍 **Any language** — every message is a template in your config (`{date}`,
  `{duration}`, `{ups}` placeholders). English, Turkish, anything.
- 🔐 **Secrets stay secret** — one root-only config file (`chmod 600`), nothing
  world-readable, helpers receive only what they need.
- 🧪 **Test everything safely** — fire test notifications and dry-run the shutdown
  without ever pulling a plug.

## 🧰 Requirements

| What | Notes |
|---|---|
| A UPS with network monitoring | Any brand NUT supports: Eaton, APC, CyberPower… (developed against an **Eaton 5E 900 G2**) |
| A NUT master on your network | Most NAS devices have it built in — **ASUSTOR, Synology, QNAP, TrueNAS** — or any Linux/BSD box running `nut-server` |
| A client machine to protect | Raspberry Pi (any model), or any Debian/Ubuntu-ish system with systemd |
| For SMS | A NetGSM account *(or use Telegram / webhook — both free)* |

> Your NAS is already the NUT master if it shows the UPS in its power settings.
> You just need to allow this client's IP / a NUT user on it (see [FAQ](#-faq)).

## 🚀 Quick start

```bash
git clone https://github.com/cankirca/upsentry.git
cd upsentry
sudo ./install.sh
```

The installer asks a handful of questions (UPS name, NUT master IP, credentials,
which notifiers you want) and does everything: installs `nut-client`, writes the
NUT and UPSentry configs, sets tight permissions, starts the service and runs a
live connection test.

### Non-interactive / scripted install

```bash
sudo ./install.sh --yes \
  --ups-name ups --nut-host 192.168.1.50 \
  --nut-user upsmon --nut-password 'secret' \
  --notifiers "telegram" \
  --telegram-token '123456:ABC...' --telegram-chat '987654' \
  --session-user devuser --session-pattern claude
```

Run `./install.sh --help` for every flag.

### Try it

```bash
sudo upsentry status             # live UPS readings through your NUT master
sudo upsentry test onbatt        # fire a REAL "power lost" notification
sudo upsentry test online        # ... and a "power restored" one
sudo upsentry simulate-shutdown  # dry-run the shutdown hook (does NOT halt)
sudo upsentry stats              # outage history & totals
sudo upsentry log 50             # last 50 log lines
```

> `sudo` is needed because the config file holding your credentials is
> readable by root only — by design.

## ⚙️ Configuration

Everything lives in **`/etc/upsentry/upsentry.conf`** (root-only, `chmod 600`).
The annotated reference is [`upsentry.conf.example`](upsentry.conf.example). Highlights:

```bash
# Which channels fire on power events (space/comma separated)
NOTIFIERS="netgsm telegram"

# Messages are templates — write them in your language
MSG_ONBATT="Power outage started: {date}"
MSG_ONLINE="Power restored: {date} (outage lasted {duration})"

# Example: Turkish
# MSG_ONBATT="Evde elektrik kesintisi basladi: {date}"
# MSG_ONLINE="Elektrik geldi: {date} (kesinti süresi: {duration})"

# Warn AI coding sessions in tmux on power loss
SESSION_NOTIFY_ENABLED="yes"
SESSION_USER="devuser"
SESSION_PROCESS_PATTERN="claude"   # matches Claude Code; use "aider", etc.
```

After editing, no restart is needed — hooks read the config on every event.

### Notifier setup

<details>
<summary><b>📱 NetGSM (SMS)</b></summary>

1. You need a NetGSM account with an approved sender title (*mesaj başlığı*).
2. Fill in `NETGSM_USERCODE`, `NETGSM_PASSWORD`, `NETGSM_HEADER` and the
   recipient `NETGSM_GSMNO` (format `5xxxxxxxxx`).
3. `sudo upsentry test onbatt` — the log should show `code=00`.

Response codes are decoded in the log (`30` bad credentials, `40` sender title
not approved, `60` no balance, `70` bad parameter…).
</details>

<details>
<summary><b>✈️ Telegram</b></summary>

1. Talk to [@BotFather](https://t.me/BotFather), create a bot, copy the token.
2. Send your bot any message, then read your chat id from
   `https://api.telegram.org/bot<TOKEN>/getUpdates`.
3. Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`, add `telegram` to `NOTIFIERS`.
</details>

<details>
<summary><b>🔔 Webhook (ntfy / Slack / Discord / Home Assistant)</b></summary>

The event message is POSTed to `WEBHOOK_URL` as the request body.

- **ntfy** (zero-setup push notifications to your phone):
  `WEBHOOK_URL="https://ntfy.sh/your-secret-topic"`
- **Slack/Discord**: use your incoming-webhook URL and set
  `WEBHOOK_CONTENT_TYPE="application/json"` — the body becomes `{"text": "..."}`.
</details>

<details>
<summary><b>🧩 Write your own notifier</b></summary>

Drop an executable script into `/opt/upsentry/notifiers/myservice.sh`:

```bash
#!/bin/bash
. /etc/upsentry/upsentry.conf      # your settings live here too
MESSAGE="$1"                       # the rendered event message
# ... deliver it ...
echo "myservice: ok"               # one result line for the log
exit 0                             # non-zero = failure (logged, never blocks others)
```

Add `myservice` to `NOTIFIERS`. Done.
</details>

## 🔍 How it works

UPSentry contains **no daemon**. NUT's `upsmon` already watches the UPS through
your master and fires events — UPSentry plugs into its two hook points:

| NUT event | What UPSentry does |
|---|---|
| `ONBATT` (power lost) | Record timestamp → notify all channels → warn matching tmux sessions |
| `ONLINE` (power back) | Compute outage duration → notify all channels |
| `LOWBATT` | Notify: shutdown imminent |
| `FSD` (forced shutdown) | Notify, then the master triggers… |
| `SHUTDOWNCMD` | Snapshot tmux layout → `sync` → clean halt |

The actual *decision* to shut down stays where it belongs — on the NUT master
(e.g. your NAS shuts everything down at 15% battery). UPSentry's client obeys
and exits gracefully.

**Real-world timing**, measured on a Raspberry Pi 5 with an Eaton 5E 900 G2
behind an ASUSTOR NAS: pull plug → client sees `OB` within seconds (master poll
interval) → **SMS accepted by the gateway 4 seconds later**.

## 🛡️ Security notes

- All credentials live in one file: `/etc/upsentry/upsentry.conf`, `root:root`, mode `600`.
- `/etc/nut/upsmon.conf` (NUT password) is `root:nut`, mode `640`.
- The session-warning helper runs as your unprivileged dev user and receives
  *only* the match pattern and message via environment — it can never read the config.
- The installer adds a systemd drop-in running `upsmon -p` (privileged mode).
  Default NUT drops the notify hook to the `nut` user, which can't read a
  root-only config nor `sudo` to your dev user. Privileged mode keeps the whole
  chain root-side while every config file stays locked down. (`-p` is an
  official upsmon mode, see `man upsmon`.)
- The tmux injector has a hard rule: **panes that don't match the process
  pattern never receive keystrokes.** Every decision is logged.

## 🧯 Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `upsc` says *Connection refused* | `upsd` on the master isn't listening on the LAN (`LISTEN 0.0.0.0 3493`) or your client IP isn't allowed |
| Master doesn't answer **ping** | Many NAS firewalls drop ICMP while NUT works fine — test with `upsc`, not ping |
| `Poll UPS failed - Driver not connected` once at startup | Harmless race while upsmon connects; it should log `Communications … established` seconds later |
| SMS log shows `code=30` | Wrong NetGSM credentials, or your server IP isn't whitelisted in the NetGSM panel |
| SMS log shows `code=40` | Sender title (`msgheader`) not approved on your NetGSM account |
| Notification hook never fires | Check `NOTIFYFLAG ... SYSLOG+EXEC` lines in `/etc/nut/upsmon.conf` and that the drop-in is active (`systemctl cat nut-monitor`) |
| Session warning not delivered | Is `SESSION_USER` correct? Does `tmux list-panes -a` (as that user) show a pane whose process matches `SESSION_PROCESS_PATTERN`? See decisions in the log |

Watch everything live during a plug-pull test:

```bash
sudo journalctl -u nut-monitor -f &
sudo tail -f /var/log/upsentry.log
```

## ❓ FAQ

**Does my NAS work as the master?**
If your NAS shows the UPS in its energy/UPS settings, it's already running a NUT
server. Allow your client: on **ASUSTOR** add the client IP under *External
Devices → UPS → Network UPS slaves*; **Synology** has *Enable network UPS server*
with a permitted-IPs list; **QNAP/TrueNAS** similar. Default NUT credentials vary
by vendor (check their docs).

**No NAS?** Run the master on any Linux box with a USB-attached UPS:
`apt install nut`, configure `ups.conf` + `upsd` — the
[NUT docs](https://networkupstools.org/docs/user-manual.chunked/index.html) cover it.

**Can I protect several machines?** Yes — install UPSentry on each client; they
all watch the same master. Set `NOTIFIERS=""` on all but one if you don't want
duplicate alerts.

**Does the SMS really go out before shutdown?** Yes. Alerts fire the moment power
is lost (`ONBATT`), while the battery still has plenty left. Shutdown only happens
much later at the master's low-battery threshold.

**What about my AI agent's unsaved work?** The tmux warning gives the agent a
chance to persist its state immediately, and the shutdown hook snapshots the
session layout so you can restore your workspace after power returns.

## 🗑️ Uninstall

```bash
sudo ./uninstall.sh    # removes UPSentry, restores your original NUT configs
```

## 🗺️ Roadmap

- [ ] Battery-level threshold alerts (e.g. notify at 50%)
- [ ] Daily/weekly outage summary reports
- [ ] E-mail notifier (msmtp)
- [ ] Prometheus textfile exporter for outage metrics
- [ ] Home Assistant MQTT discovery

PRs welcome — a notifier is a ~20-line bash script; see *Write your own
notifier* under the Configuration section above.

## 📄 License

[MIT](LICENSE) — do anything, just keep the notice.

---

*Built on a Raspberry Pi 5 during an actual Turkish summer of flaky power.*
*Tested by literally pulling the plug.* Powered by [Network UPS Tools](https://networkupstools.org/).
