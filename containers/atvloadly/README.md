# atvloadly

IPA sideloading for Apple TV without Xcode, plus tooling to back up/restore the
pairing & Apple ID session and a host-side systemd service that refreshes the
apps on a schedule and pushes a notification with the result (success or failure).
Upstream: [bitxeno/atvloadly](https://github.com/bitxeno/atvloadly).

|              |                                          |
|--------------|------------------------------------------|
| **Upstream** | [bitxeno/atvloadly](https://github.com/bitxeno/atvloadly) |
| **Image**    | `bitxeno/atvloadly:latest`               |
| **Web UI**   | `http://<host>:5533`                     |
| **Storage**  | `/etc/atvloadly` (host bind) → `/data`   |
| **Network**  | `host` (publishes `5533:80`)             |
| **Host deps**| `avahi-daemon`, host `dbus`              |

## Prerequisites

- Docker engine — see [host setup](../../docs/host-setup.md).
- **avahi** (this stack bind-mounts the host avahi/dbus sockets for device discovery):
  ```bash
  sudo apt install -y avahi-daemon
  sudo systemctl enable --now avahi-daemon
  ```

## Deploy

```bash
mkdir -p ~/docker/atvloadly && cd ~/docker/atvloadly
wget https://raw.githubusercontent.com/hshamsaldin/atvloadly/main/docker-compose.yml
docker compose up -d
```

State lives at the host path `/etc/atvloadly` (mounted as `/data`): pairing files,
Apple ID session, app database, settings — this is the backup target below.

## Upgrade

```bash
cd ~/docker/atvloadly
docker compose pull && docker compose up -d
```

## Verify

```bash
docker compose ps
docker logs atvloadly
curl -sI http://localhost:5533 | head -1
```

Web UI: `http://<host>:5533`.

## Backup

A clean backup excludes the heavy `.ipa` payloads and keeps only what's needed to
avoid re-pairing/re-login on a fresh install:

```bash
sudo tar -czf ~/atvloadly-backup-$(date +%Y-%m-%d)-clean.tar.gz \
  -C /etc/atvloadly \
  --exclude='ipa' --exclude='*.ipa' --exclude='tmp' --exclude='log' .
```

Keeps: `PlumeImpactor/` (pairing record, `accounts.json` session, `adi.pb` +
`keys/*/key.pem` Anisette identity, CoreADI/storeservicescore libs),
`lockdown/SystemConfiguration.plist`, `app.db`, `settings.json`, `config.yaml`.
Drops: `ipa/` payloads, stray `*.ipa`, `tmp/`, `log/`.

Copy it off the host:

```bash
scp <user>@<host>:~/atvloadly-backup-*-clean.tar.gz "C:\path\to\backups\"
```

### Restore

On a fresh host (or after wiping `/etc/atvloadly`):

```bash
sudo docker stop atvloadly
sudo mv /etc/atvloadly /etc/atvloadly.bak-$(date +%s) 2>/dev/null || true
sudo mkdir -p /etc/atvloadly
sudo tar -xzf atvloadly-backup-YYYY-MM-DD-clean.tar.gz -C /etc/atvloadly
ls -la /etc/atvloadly   # expect: PlumeImpactor/ lockdown/ app.db settings.json config.yaml
sudo docker start atvloadly
sudo docker logs -f atvloadly
```

A successful restore shows `Restoring session for <your-apple-id>...` then device
registration and install — with no pairing/login prompt in between.

If the archive is **corrupted/truncated**, `tar` processes entries sequentially,
so you can still recover everything before the break:

```bash
tar -xzf backup.tar.gz -C /restore/dest \
  atvloadly/PlumeImpactor atvloadly/lockdown atvloadly/app.db \
  atvloadly/settings.json atvloadly/config.yaml
```

## Tooling

Helper scripts in [`scripts/`](scripts) for install + a self-contained host
refresh-and-notify service.

| File | Runs on | Purpose |
|---|---|---|
| `Install-AppleTVApp_v2.ps1` | Windows | scp a new IPA to the host and install it via the MCP API |
| `Refresh-AppleTVApp.ps1` | Windows | Force a refresh via MCP and notify with the real result |
| `atvloadly-refresh.sh` | host | Force-refresh enabled apps via MCP, wait for completion, push the `ok/failed` result |
| `atvloadly-refresh.service` | host (systemd) | oneshot unit that runs the refresh script |
| `atvloadly-refresh.timer` | host (systemd) | Triggers the refresh daily at 20:30 |

**Refresh from Windows:**
```powershell
& .\Refresh-AppleTVApp.ps1 -PiHost <host> -AppId 4   # one app, forced
& .\Refresh-AppleTVApp.ps1 -PiHost <host>            # all expired/near-expiry
```

**Scheduled refresh-and-notify on the host:**
```bash
cp scripts/atvloadly-refresh.sh ~/atvloadly-refresh.sh && chmod +x ~/atvloadly-refresh.sh
sudo cp scripts/atvloadly-refresh.service scripts/atvloadly-refresh.timer /etc/systemd/system/
# edit /etc/systemd/system/atvloadly-refresh.service first: set User= and the ExecStart path
sudo systemctl daemon-reload
sudo systemctl enable --now atvloadly-refresh.timer
```

## Notes

- **Security deviation (intentional):** runs `seccomp:unconfined` and mounts host
  `dbus`/`avahi` sockets — required for USB/usbmuxd pairing. Do **not** add
  `no-new-privileges` / `cap_drop: ALL` here; it breaks pairing.
- **Edit the systemd unit before enabling:** `atvloadly-refresh.service` ships
  with `User=YOUR_USER` / `/home/YOUR_USER/...` placeholders — set your real user
  and path first.
- **Turn off atvloadly's built-in Auto-Refresh** (Settings → Task → Enable off) so
  only this host timer drives refreshes. Change the time by editing the
  `OnCalendar=` line in `atvloadly-refresh.timer` and running `sudo systemctl daemon-reload`.
- **Container runs on `Europe/Amsterdam`** (`TZ` + `/etc/localtime` mount in the
  compose) so both the timer and any in-app schedule use local wall-clock time, not UTC.
- Upstream publishes only `:latest` — upgrade with `docker compose pull && docker compose up -d`.

---
_Tested on: `raspberrypi` (linux/arm64) — deploy, backup, and restore are from the
working setup documented in [hshamsaldin/atvloadly](https://github.com/hshamsaldin/atvloadly)._
