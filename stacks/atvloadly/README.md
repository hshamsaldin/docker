# atvloadly

Web tool for sideloading IPAs to Apple TV without Xcode.
Full setup, backup/restore, and auto-refresh tooling:
https://github.com/hshamsaldin/atvloadly

- **Image:** `bitxeno/atvloadly:latest` (upstream publishes only `latest`)
- **Web UI:** http://<pi-ip>:5533
- **Storage:** host bind mount `/etc/atvloadly` -> `/data` — holds pairing files,
  Apple ID session, ADI/anisette identity, `app.db`, `settings.json`, `config.yaml`.
  This is the directory you back up; do not wipe it or you must re-pair / re-login.

## Host prerequisite — avahi + dbus

This stack bind-mounts the host's avahi and dbus sockets for device discovery,
so avahi must be installed and running on the Pi first:

```bash
sudo apt install -y avahi-daemon
sudo systemctl enable --now avahi-daemon
```

## Security note (intentional deviation from the repo standard)

Unlike other stacks, this one runs `seccomp:unconfined` and mounts host
dbus/avahi sockets because sideloading needs broad device access. These are
required by upstream — do **not** add `no-new-privileges` / `cap_drop: ALL`
here, it breaks USB/usbmuxd pairing. The trade-off is accepted for this app.

## Deploy / upgrade

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

## Backup the pairing/session state

Small clean backup (excludes heavy .ipa payloads):

```bash
sudo tar -czf ~/atvloadly-backup-$(date +%F)-clean.tar.gz \
  -C /etc/atvloadly --exclude='ipa' --exclude='*.ipa' \
  --exclude='tmp' --exclude='log' .
```

Restore + refresh tooling (PowerShell + systemd timer) is documented in the
companion repo linked at the top.
