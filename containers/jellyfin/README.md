# Jellyfin

Free Software media server — streams your movies/shows to any device.

|              |                                          |
|--------------|------------------------------------------|
| **Upstream** | [jellyfin/jellyfin](https://github.com/jellyfin/jellyfin) (GPL-2.0) |
| **Image**    | `jellyfin/jellyfin:latest`               |
| **Web UI**   | `http://<host>:8096`                      |
| **Storage**  | `./config`, `./cache` (bind) · media disk → `/data` (bind, read-only) |
| **Network**  | `jellyfin_net` (bridge), publishes `8096` |
| **Host deps**| media disk mounted via `/etc/fstab` at `MEDIA_PATH` |

## Prerequisites

- Docker engine + compose plugin — see [host setup](../../docs/host-setup.md).
- Media disk mounted on the host at `MEDIA_PATH`. Values are **per-host** — discover
  this machine's, never copy another's:

  1. **Read the partition's UUID and filesystem type** (don't assume `ext4`):
     ```bash
     lsblk -f          # note the data partition's UUID and FSTYPE
     ```
  2. **Install the driver** if it's a foreign filesystem (native ext4/xfs/btrfs need none):
     ```bash
     sudo apt install -y ntfs-3g       # NTFS  (Windows-formatted disks)
     sudo apt install -y exfatprogs    # exFAT
     ```
  3. **Add one line to `/etc/fstab`**, substituting your own `UUID`, `FSTYPE`, and —
     for NTFS/exFAT — your `id -u`/`id -g`. `nofail` keeps boot from hanging if the
     disk is absent:
     ```
     # native Linux fs (ext4/xfs/btrfs):
     UUID=<uuid>  /mnt/media  <fstype>  defaults,nofail  0  2
     # foreign fs (ntfs-3g / exfat) — read-only is all Jellyfin needs:
     UUID=<uuid>  /mnt/media  ntfs-3g   ro,nofail,uid=<uid>,gid=<gid>,umask=022  0  0
     ```
  4. **Mount and confirm:**
     ```bash
     sudo mkdir -p /mnt/media
     sudo mount -a && ls /mnt/media
     ```

## Deploy

Copy `docker-compose.yml` and `.env.example` from this folder
(`containers/jellyfin/`) onto the host, then bring it up:

```bash
mkdir -p ~/docker/jellyfin && cd ~/docker/jellyfin
# place this folder's docker-compose.yml and .env.example here first
cp .env.example .env                   # then edit PUID/PGID/TZ/MEDIA_PATH
docker compose up -d
```

Open `http://<host>:8096`, run the setup wizard, and point libraries at
`/data` (e.g. `/data/Movies`, `/data/Shows`).

## Upgrade

```bash
cd ~/docker/jellyfin
docker compose pull && docker compose up -d
```

## Verify

```bash
docker compose ps                      # State should be "running"
docker compose logs -f jellyfin        # watch for startup errors
# then load the Web UI and confirm a library scan finds your media
```

## Backup

```bash
# bind mount — just tar the config (media is not backed up here):
tar czf jellyfin-$(date +%F).tar.gz -C ~/docker/jellyfin/config .
```

## Notes

- **Deviation — `/data` is the media disk, not `./data`.** The repo standard
  binds app data to `./data` next to the compose file. Here, container `/data`
  is instead the external media disk (`${MEDIA_PATH}`, read-only), because the
  media is terabytes on a mounted drive, not app state. Jellyfin's actual
  writable data lives in `./config` + `./cache` (both binds next to compose),
  which is where the image expects it — so the standard's intent (app data
  next to compose, never inside the container) still holds.
- **Deviation — `mem_limit: 4g`** (baseline is 512m). Transcoding is
  memory-hungry; 512m will OOM on any real transcode.
- **Deviation — no `read_only` rootfs.** Jellyfin writes transcode temp and
  runtime state beyond `/config` and `/cache`; a read-only root is not
  verified safe here, so it's left off per the no-guessing rule.
- **`/data` is read-only** — Jellyfin never writes to your media. If you later
  use Jellyfin features that write back (e.g. saving `.nfo` metadata next to
  files), drop `read_only: true` on that mount.
- **Reverse proxy:** if fronting with Caddy, switch the port line to
  `127.0.0.1:8096:8096` and join the shared `proxy` network instead.
- **DLNA / client auto-discovery** needs host networking, which this bridge
  setup does not provide. Access by IP/URL works fine; only LAN
  auto-discovery is affected.
- **Hardware transcoding:** uncomment the `/dev/dri` device for Intel/AMD
  VAAPI, then enable it in Dashboard → Playback.

---
_⚠️ UNTESTED — not yet run on a real host. Verify each command, then replace
this line with `Tested on: <host>, <YYYY-MM-DD>`._
