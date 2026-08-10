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
- **pyatv** (only needed for the `wake-appletv.sh` refresh helper below — waking the
  Apple TV before a scheduled refresh):
  ```bash
  sudo apt install -y python3-venv
  python3 -m venv ~/atvloadly/pyatv-venv
  ~/atvloadly/pyatv-venv/bin/pip install pyatv
  ```
  Use a venv, not system/Docker pip — Debian's apt-owned `python3-cryptography` blocks
  a `--break-system-packages` install, and the official `pyatv` Docker image crashes
  on `atvremote` with a Python 3.14 asyncio bug. A venv sidesteps both.

  Pair once per device (PIN shows on the TV):
  ```bash
  ~/atvloadly/pyatv-venv/bin/atvremote --scan-hosts <atv-ip> --id "<atv-id>" --protocol companion pair
  ```
  Credentials auto-save to `~/.pyatv.conf` (not `~/.config/pyatv/`, despite some docs).
  Find `<atv-id>` with `~/atvloadly/pyatv-venv/bin/atvremote --scan-hosts <atv-ip> scan`
  — it's pyatv's own identifier, not the device's ARP/router MAC; the two can differ.

## Deploy

Copy `docker-compose.yml` from this folder (`containers/atvloadly/`) onto the host,
then bring it up:

```bash
mkdir -p ~/docker/atvloadly && cd ~/docker/atvloadly
# place containers/atvloadly/docker-compose.yml in this directory first
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

**Also back up `~/.pyatv.conf`** if you use `wake-appletv.sh` — it's the pyatv
pairing credentials for the Apple TV, lives directly in the home dir (not under
`/etc/atvloadly`, and not `~/.config/pyatv/` despite some docs), and isn't covered
by the tar above:

```bash
cp ~/.pyatv.conf ~/atvloadly-backup-pyatv-$(date +%Y-%m-%d).conf
scp <user>@<host>:~/atvloadly-backup-pyatv-*.conf "C:\path\to\backups\"
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

Restore `~/.pyatv.conf` too if you use `wake-appletv.sh`:

```bash
cp ~/atvloadly-backup-pyatv-YYYY-MM-DD.conf ~/.pyatv.conf
~/atvloadly/pyatv-venv/bin/atvremote --scan-hosts <atv-ip> --id "<atv-id>" power_state
```

If that returns a real state (not an auth error), the credentials are valid and
re-pairing isn't needed.

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
| `wake-appletv.sh` | host | Wake the Apple TV via pyatv if it's asleep (runs as `ExecStartPre`, before the refresh) |
| `atvloadly-refresh.sh` | host | Force-refresh enabled apps via MCP, wait for completion, push the `ok/failed` result |
| `atvloadly-refresh.service` | host (systemd) | oneshot unit: wakes the Apple TV, then runs the refresh script |
| `atvloadly-refresh.timer` | host (systemd) | Triggers the refresh every 4 days |

**Refresh from Windows:**
```powershell
& .\Refresh-AppleTVApp.ps1 -PiHost <host> -AppId 4   # one app, forced
& .\Refresh-AppleTVApp.ps1 -PiHost <host>            # all expired/near-expiry
```

**Scheduled refresh-and-notify on the host:**

These three scripts live together in `~/atvloadly/` (the systemd unit's
`ExecStartPre`/`ExecStart` paths assume this layout) — separate from
`~/docker/atvloadly/`, which only holds `docker-compose.yml`.

```bash
cp scripts/wake-appletv.sh scripts/atvloadly-refresh.sh ~/atvloadly/
chmod +x ~/atvloadly/wake-appletv.sh ~/atvloadly/atvloadly-refresh.sh
# edit ~/atvloadly/wake-appletv.sh first: set ATV_IP / ATV_ID / ATV_REMOTE
# (skip this and the ExecStartPre line below if you don't use pyatv wake)
sudo cp scripts/atvloadly-refresh.service scripts/atvloadly-refresh.timer /etc/systemd/system/
# edit /etc/systemd/system/atvloadly-refresh.service first: set User= and the
# ExecStartPre/ExecStart paths (both are /home/YOUR_USER/atvloadly/...)
sudo systemctl daemon-reload
sudo systemctl enable --now atvloadly-refresh.timer
```

Test the refresh script directly with `bash ~/atvloadly/atvloadly-refresh.sh` or
`sudo systemctl start atvloadly-refresh.service` — **never** `sudo bash
atvloadly-refresh.sh`: root's `$HOME` is `/root`, not your user's home, so the log
path silently breaks.

## Notes

- **Security deviation (intentional):** runs `seccomp:unconfined` and mounts host
  `dbus`/`avahi` sockets — required for USB/usbmuxd pairing. Do **not** add
  `no-new-privileges` / `cap_drop: ALL` here; it breaks pairing.
- **Edit the systemd unit before enabling:** `atvloadly-refresh.service` ships
  with `User=YOUR_USER` / `/home/YOUR_USER/...` placeholders — set your real user
  and path first.
- **Turn off atvloadly's built-in Auto-Refresh** (Settings → Task → Enable off) so
  only this host timer drives refreshes. Change the cadence by editing the
  `OnCalendar=` line in `atvloadly-refresh.timer` and running `sudo systemctl daemon-reload`.
  `OnCalendar=*-*-01/4 00:00:00` resets its day-count at every month boundary, so
  near month-end the real gap is sometimes 1–3 days instead of 4 — it only ever
  fires early, never late, which is the point (an early refresh is harmless, a late
  one risks the cert actually expiring).
- **Container runs on `Europe/Amsterdam`** (`TZ` + `/etc/localtime` mount in the
  compose) so both the timer and any in-app schedule use local wall-clock time, not UTC.
- **pyatv gotchas**, if using `wake-appletv.sh`: `atvremote`'s target flags
  (`--scan-hosts`/`-s`, `--id`, `--protocol`) must come *before* the action command
  (`pair`, `scan`, `turn_on`) — `--scan-hosts pair` fails, it tries to parse `pair`
  as an IP. Plain `atvremote scan` (multicast/mDNS) is unreliable on some networks —
  prefer `--scan-hosts <ip>` (unicast). If another device on the network shares the
  Apple TV's mDNS name, target by `--id`/IP, never `-n <name>`. Some HDMI-CEC setups
  cascade Apple TV power state to other devices on the same TV (e.g. a console going
  to sleep too) — if that's unwanted, disable the offending device's HDMI power-link
  option, not this script's wake behavior.
- Upstream publishes only `:latest` — upgrade with `docker compose pull && docker compose up -d`.

---
_Tested on: `raspberrypi` (linux/arm64) — deploy, backup, and restore are from the
working setup documented in [hshamsaldin/atvloadly](https://github.com/hshamsaldin/atvloadly)._
