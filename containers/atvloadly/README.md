# atvloadly

IPA sideloading for Apple TV without Xcode, plus tooling to back up/restore the
pairing & Apple ID session and get a push notification for every refresh attempt
(not just failures, which is all the built-in scheduler reports).
Upstream: [bitxeno/atvloadly](https://github.com/bitxeno/atvloadly).

|              |                                          |
|--------------|------------------------------------------|
| **Image**    | `bitxeno/atvloadly:latest` (upstream ships only `latest`) |
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

Helper scripts in [`scripts/`](scripts) for refresh/install + always-on notifications.

| File | Runs on | Purpose |
|---|---|---|
| `Install-AppleTVApp_v2.ps1` | Windows | scp a new IPA to the host and install it via the MCP API |
| `Refresh-AppleTVApp.ps1` | Windows | Force a refresh via MCP and notify with the real result |
| `atvloadly-status-check.sh` | host | Check refresh status via REST API, notify, and log |
| `atvloadly-status-check.service` | host (systemd) | oneshot unit that runs the status-check script |
| `atvloadly-status-check.timer` | host (systemd) | Runs the service 15 min after atvloadly's own refresh window |

**Refresh from Windows:**
```powershell
& .\Refresh-AppleTVApp.ps1 -PiHost <host> -AppId 4   # one app, forced
& .\Refresh-AppleTVApp.ps1 -PiHost <host>            # all expired/near-expiry
```

**Always-notify timer on the host:**
```bash
cp scripts/atvloadly-status-check.sh ~/atvloadly-status-check.sh && chmod +x ~/atvloadly-status-check.sh
sudo cp scripts/atvloadly-status-check.service scripts/atvloadly-status-check.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now atvloadly-status-check.timer
```

## Notes

- **Security deviation (intentional):** runs `seccomp:unconfined` and mounts host
  `dbus`/`avahi` sockets — required for USB/usbmuxd pairing. Do **not** add
  `no-new-privileges` / `cap_drop: ALL` here; it breaks pairing.
- **Edit the systemd unit before enabling:** `atvloadly-status-check.service` ships
  with `User=YOUR_USER` / `/home/YOUR_USER/...` placeholders — set your real user
  and path first.
- **Timer schedule is not auto-linked** to atvloadly's in-app refresh schedule. If
  you change it in Settings → Task, update `atvloadly-status-check.timer` and run
  `sudo systemctl daemon-reload`.
- Upstream publishes only `:latest`, so this stack can't pin a version tag the way
  the standard prefers; pin by image digest if you need clean rollbacks.
