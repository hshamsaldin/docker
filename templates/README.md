<!--
CONTAINER README TEMPLATE — copy this to containers/<app>/README.md and fill in.
Keep the section order below for EVERY container. Delete sections only if truly
N/A (e.g. "Backup" for a stateless app) and say why. Keep it short; link out
for deep guides instead of pasting walls of text.
-->
# <Name>

<One-sentence description of what it does.>

|              |                                          |
|--------------|------------------------------------------|
| **Upstream** | [vendor/project](https://github.com/vendor/project) |
| **Image**    | `vendor/image:tag`                       |
| **Web UI**   | `http://<host>:PORT` (or `—`)            |
| **Storage**  | `<source>` → `<container path>`          |
| **Network**  | `<app>_net` (default) / `host` / `proxy` |
| **Host deps**| `<e.g. avahi, dbus>` (or `—`)            |

## Prerequisites

<Host packages, shared networks, setup keys — or "None." Link to
[host setup](../../docs/host-setup.md) for Docker engine itself.>

## Deploy

```bash
cd ~/docker/<app>
docker compose up -d
```

## Upgrade

```bash
cd ~/docker/<app>
docker compose pull && docker compose up -d
```

## Verify

```bash
docker compose ps
# + the app's own health/status check
```

## Backup

<How to back up the persistent data — or "None — stateless.">

## Notes

- <Any deliberate deviation from the repo standard, and why.>
- <Gotchas, links to deeper docs.>

---
_Tested on: `<host>`, `<YYYY-MM-DD>` — all commands above run and verified._
