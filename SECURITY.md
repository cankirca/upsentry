# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.x     | ✅        |

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private vulnerability reporting instead:
**Security → Report a vulnerability** on this repository
(https://github.com/cankirca/upsentry/security/advisories/new).

You can expect an initial response within a few days. Once a fix is
released, the report will be credited (unless you prefer otherwise).

## Scope notes

UPSentry runs with root privileges by design (it must shut the machine
down and read a root-only config). Reports are especially welcome for:

- privilege-boundary issues around the session-warning helper
  (it must never run config-derived code as the unprivileged user)
- injection via NUT-supplied values (`NOTIFYTYPE`, `UPSNAME`)
- credential exposure through logs, process listings or file permissions
