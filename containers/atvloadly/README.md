# atvloadly — Raspberry Pi setup, backup/restore, and auto-refresh notifications

This repo documents a full working setup of [atvloadly](https://github.com/bitxeno/atvloadly)
(IPA sideloading for Apple TV without Xcode) running in Docker on a Raspberry Pi,
plus tooling to back up/restore the pairing & Apple ID session, trigger refreshes
on demand, and get real push notifications for every refresh attempt (not just
failures, which is all the built-in scheduler notifies on).

## Contents

- [Part 1 — Install Docker Engine](#part-1--install-docker-engine)
- [Part 2 — Install avahi-daemon](#part-2--install-avahi-daemon)
- [Part 3 — Install and run atvloadly](#part-3--install-and-run-atvloadly)
- [Part 4 — Verify atvloadly is running](#part-4--verify-atvloadly-is-running)
- [Backup](#backup)
- [Restore](#restore)
- [Refresh apps — from Windows (PowerShell)](#refresh-apps--from-windows-powershell)
- [Refresh apps — from the Pi (systemd timer)](#refresh-apps--from-the-pi-systemd-timer)
- [Scripts reference](#scripts-reference)

---

## Part 1 — Install Docker Engine

**Step 1 — Remove conflicting packages**

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt remove $pkg
done
```

**Step 2 — Add Docker's official repo**

```bash
sudo apt update
sudo apt install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
```

**Step 3 — Install Docker**

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

**Step 4 — Run Docker without sudo (optional but convenient)**

```bash
sudo usermod -aG docker $USER
newgrp docker
```

## Part 2 — Install avahi-daemon

atvloadly's `docker-compose.yml` bind-mounts `/var/run/avahi-daemon` from the host
for network device discovery, so avahi must be installed and running on the host
first:

```bash
sudo apt install -y avahi-daemon
sudo systemctl enable --now avahi-daemon
```

## Part 3 — Install and run atvloadly

```bash
mkdir -p /opt/atvloadly && cd /opt/atvloadly

# use the docker-compose.yml from this repo
wget https://raw.githubusercontent.com/hshamsaldin/atvloadly/main/docker-compose.yml

docker compose pull
docker compose up -d
```

The compose file mounts the host path `/etc/atvloadly` as `/data` inside the
container — that's where all persistent state lives (pairing files, Apple ID
session, app database, settings). This is the directory that gets backed up
and restored below.

## Part 4 — Verify atvloadly is running

```bash
docker ps
docker logs atvloadly
```

Web UI: `http://<your-debian-host-ip>:5533`

---

## Backup

A clean backup excludes the heavy sideloaded `.ipa` payloads and only keeps the
pairing record, Apple ID session, ADI/anisette identity, and app config — small,
fast, and everything you actually need to avoid re-pairing/re-login on a fresh
install:

```bash
sudo tar -czf ~/atvloadly-backup-$(date +%Y-%m-%d)-clean.tar.gz \
  -C /etc/atvloadly \
  --exclude='ipa' \
  --exclude='*.ipa' \
  --exclude='tmp' \
  --exclude='log' \
  .
```

This keeps:

- `PlumeImpactor/` — `pairing_files/*.plist|.json` (the actual Apple TV pairing
  record), `accounts.json` (signed-in Apple ID session), `adi.pb` + `keys/*/key.pem`
  (Anisette device identity), `identifier`, and the CoreADI/storeservicescore libs
- `lockdown/SystemConfiguration.plist`
- `app.db`, `settings.json`, `config.yaml`

And drops:

- `ipa/` — all installed app payloads
- any stray `*.ipa` source files at the root
- `tmp/` and `log/` — transient, not needed for restore

Copy it off the Pi for safekeeping:

```bash
scp <user>@<pi-ip>:~/atvloadly-backup-*-clean.tar.gz "C:\path\to\backups\"
```

## Restore

On a fresh Pi/SD card (or after wiping `/etc/atvloadly`):

```bash
# 1. Stop the container
sudo docker stop atvloadly

# 2. Back up whatever's currently in /etc/atvloadly (if anything)
sudo mv /etc/atvloadly /etc/atvloadly.bak-$(date +%s) 2>/dev/null || true

# 3. Extract the backup directly into place
sudo mkdir -p /etc/atvloadly
sudo tar -xzf atvloadly-backup-YYYY-MM-DD-clean.tar.gz -C /etc/atvloadly

# 4. Sanity check the layout
ls -la /etc/atvloadly
# expect: PlumeImpactor/  lockdown/  app.db  settings.json  config.yaml

# 5. Restart the container
sudo docker start atvloadly

# 6. Watch the logs — should NOT prompt to re-pair or re-login
sudo docker logs -f atvloadly
```

Confirmation that the restore worked: the logs should show

```
Restoring session for <your-apple-id>...
Registering device: AppleTV (00008110-...)
...
Installing ipa success: <name>
```

with no pairing/login prompt in between. The session and pairing record from
the backup are being reused directly.

If recovering from a **corrupted/truncated** backup archive (e.g. a flaky SD
card read), `tar` may error out partway through, but since it processes
entries sequentially you can often still recover everything that comes before
the corruption point:

```bash
tar -xzf backup.tar.gz -C /restore/dest atvloadly/PlumeImpactor atvloadly/lockdown atvloadly/app.db atvloadly/settings.json atvloadly/config.yaml
```

This ignores the trailing tar error and still writes out the files matched
before the stream broke.

---

## Refresh apps — from Windows (PowerShell)

[`scripts/Refresh-AppleTVApp.ps1`](scripts/Refresh-AppleTVApp.ps1) drives
atvloadly's MCP API (`/mcp`) to force a refresh and report the real result,
unlike the built-in scheduler which stays silent on success:

```powershell
# Refresh a specific app by id (forces it regardless of expiry)
& .\Refresh-AppleTVApp.ps1 -PiHost <pi-ip> -AppId 4

# Refresh all apps that are actually expired/near-expiry (mirrors the built-in scheduler)
& .\Refresh-AppleTVApp.ps1 -PiHost <pi-ip>
```

It initializes an MCP session, calls the `refresh_app` tool, polls
`get_refresh_status` until done, then sends one notification via atvloadly's
own `/api/notify/send` endpoint (reusing whatever webhook is already configured
in Settings → Notification) with the real per-app result.

[`scripts/Install-AppleTVApp_v2.ps1`](scripts/Install-AppleTVApp_v2.ps1) is the
companion script for installing a *new* IPA: it copies the file to
`/etc/atvloadly` over `scp`, then drives the same MCP API
(`get_device_list` → `get_account_list` → `install_app` → poll
`get_install_status`) to sign and push it to the paired Apple TV.

## Refresh apps — from the Pi (systemd timer)

atvloadly's own scheduled task (configured in Settings → Task, e.g.
`0,30 20-21 * * *`) refreshes expiring apps automatically but **only sends a
notification on failure** — a successful refresh is silent. To get a
notification either way (and a persistent log), there's a companion systemd
timer that runs 15 minutes after each scheduled window and reports the actual
result:

```bash
# 1. Script: scripts/atvloadly-status-check.sh -> ~/atvloadly-status-check.sh
chmod +x ~/atvloadly-status-check.sh

# 2. Service + timer units -> /etc/systemd/system/
sudo cp scripts/atvloadly-status-check.service /etc/systemd/system/
sudo cp scripts/atvloadly-status-check.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now atvloadly-status-check.timer

# Check next scheduled run
systemctl list-timers atvloadly-status-check.timer

# Manually trigger once to test
sudo systemctl start atvloadly-status-check.service
journalctl -u atvloadly-status-check.service -n 20 --no-pager
```

The script queries `/api/apps`, builds a per-app `OK` / `FAIL` report from the
`refreshed_result` / `refreshed_error` / `expiration_date` fields, sends it via
`/api/notify/send` (always, success or failure), and appends a timestamped line
to `~/atvloadly-status-check.log` on every run regardless of
whether it notified.

**Note:** the timer's `OnCalendar` schedule is hardcoded to 15 minutes after
atvloadly's *current* refresh schedule. If you change the schedule in
atvloadly's Settings UI, update `atvloadly-status-check.timer` and run
`sudo systemctl daemon-reload` again — they aren't linked automatically.

---

## Scripts reference

| File | Runs on | Purpose |
|---|---|---|
| `scripts/Install-AppleTVApp_v2.ps1` | Windows | scp a new IPA to the Pi and install it via the MCP API |
| `scripts/Refresh-AppleTVApp.ps1` | Windows | Force/trigger a refresh via MCP and notify with the real result |
| `scripts/atvloadly-status-check.sh` | Pi | Check current app refresh status via REST API, notify, and log |
| `scripts/atvloadly-status-check.service` | Pi (systemd) | oneshot unit that runs the status-check script |
| `scripts/atvloadly-status-check.timer` | Pi (systemd) | Schedules the service 15 min after atvloadly's own refresh window |
