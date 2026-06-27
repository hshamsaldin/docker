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
  3. **Create the mount point** (must exist before fstab/mount). We mount at `/data`
     so the host path matches the container path — same `/data` everywhere:
     ```bash
     sudo mkdir -p /data
     ```
  4. **Add one line to `/etc/fstab`**, substituting your own `UUID`, `FSTYPE`, and —
     for NTFS/exFAT — your `id -u`/`id -g`. `nofail` keeps boot from hanging if the
     disk is absent:
     ```
     # native Linux fs (ext4/xfs/btrfs):
     UUID=<uuid>  /data  <fstype>  defaults,nofail  0  2
     # foreign fs (ntfs-3g / exfat) — read-only is all Jellyfin needs:
     UUID=<uuid>  /data  ntfs-3g   ro,nofail,uid=<uid>,gid=<gid>,umask=022  0  0
     ```
  5. **Reload systemd, mount, and confirm** (the `daemon-reload` is needed after
     editing fstab, or systemd warns it's using the old version):
     ```bash
     sudo systemctl daemon-reload
     sudo mount -a
     ls /data          # your media should list — same path the container sees
     ```

## Deploy

Copy `docker-compose.yml` and `.env.example` from this folder
(`containers/jellyfin/`) onto the host, then bring it up:

```bash
mkdir -p ~/docker/jellyfin && cd ~/docker/jellyfin
# place this folder's docker-compose.yml and .env.example here first
cp .env.example .env                   # then edit PUID/PGID/TZ/MEDIA_PATH

# config/cache must be writable by PUID:PGID. If Docker auto-creates them they
# come up root-owned and Jellyfin crash-loops on "Access to the path
# '/config/log' is denied" — so create them owned by your user first:
mkdir -p config cache
sudo chown -R "$(id -u):$(id -g)" config cache

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

## Subtitle tooling

`scripts/ManageSubtitles.sh` attaches external subtitle files to episodes so
Jellyfin auto-detects them. Run it on the **host** with **no arguments** — it lists
your shows (pick by number), lists that show's seasons (pick the one your zip is
for, or `0` for all), asks for the subtitles and language, previews the mapping,
and on `y` copies each sub **beside its episode** as `<video-basename>.<lang>.srt`
(or `.ass`, …), archives a copy in `Subtitles/`, flattens any `Season NN/Season NN`,
and can trigger a Jellyfin library scan. Needs `python3` + `curl`.

| File | Runs on | Purpose |
|---|---|---|
| `scripts/ManageSubtitles.sh` | host | interactive: match subs to episodes, place beside videos, archive, flatten, optional scan |

**Workflow:** download the subtitle zip on your PC → `scp` it to the host → run the
script (it reads a **local path**, so the zip must already be there):
```powershell
# on Windows (PowerShell): copy the zip to the host
scp "C:\path\subs.zip" user@<host>:/tmp/subs.zip
```

Install once:
```bash
sudo cp scripts/ManageSubtitles.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/ManageSubtitles.sh
```

Then just run it — no options:
```bash
ManageSubtitles.sh
```
and answer the prompts:
```
Shows under /data/jellyfin/Shows:
  1- Game of Thrones
Show (number or name): 1
Seasons in Game of Thrones:
  0- All seasons
  1- Season 04
  2- Season 05
  3- Season 06
Season (number or name) [0=all]: 3
Subtitles .zip or folder [/tmp/subs.zip]: /tmp/subs.zip
Language tag [ara]:
----- preview -----
S06E01  Game.of.Thrones.S06E01...srt  ->  Game.Of.Thrones.S06E01.BluRay.4K.UHD.H265.ara.srt
...
DRY-RUN  matched=10  missing=0
Applies to: Season 06
Apply (place + archive + flatten)? [y/N] y
Jellyfin API key for auto-scan (blank to skip):
```

Shows resolve under `$JELLYFIN_SHOWS` (default `/data/jellyfin/Shows`); the scan
hits `$JELLYFIN_URL` (default `http://localhost:8096`). Matches
`.srt .ass .ssa .vtt .sub`, normalizes naming (`E1`→`E01`, dots/underscores),
language defaults to `ara` (3-letter ISO 639-2). **Only seasons present in the
subtitle source are touched** — feed an S06 zip and it acts on S06 only, ignoring
the other seasons.

**API key for the auto-scan:** Jellyfin **Dashboard → Advanced → API Keys → ➕**,
name it, copy it, and paste it at the prompt (leave blank to skip the scan). The
scan POSTs `/Library/Refresh` with `Authorization: MediaBrowser Token="<key>"`
and is successful on `HTTP 204` — same as Dashboard → Scan All Libraries.

## Notes

- **Deviation — `/data` is the media disk, not `./data`.** The repo standard
  binds app data to `./data` next to the compose file. Here, container `/data`
  is instead the external media disk (`${MEDIA_PATH}`, read-only), because the
  media is terabytes on a mounted drive, not app state. Jellyfin's actual
  writable data lives in `./config` + `./cache` (both binds next to compose),
  which is where the image expects it — so the standard's intent (app data
  next to compose, never inside the container) still holds.
- **Deviation — `mem_limit: 2g`** (above the 512m baseline). This host is a
  Raspberry Pi 4B with **3.7 GiB RAM**, so 2g is a ceiling that gives transcoding
  headroom while leaving room for the OS and the other containers. Tune with
  `docker stats Jellyfin` once real usage is observed.
  **Caveat (verified on this host):** Raspberry Pi OS ships with the memory
  cgroup disabled, so Docker prints `memory limit capabilities … Limitation
  discarded` and ignores `mem_limit` (and `docker stats` shows `0B / 0B`). To
  actually enforce it, append `cgroup_enable=memory cgroup_memory=1` to the
  single line in `/boot/firmware/cmdline.txt` and reboot.
- **Deviation — no `read_only` rootfs.** A read-only root is **not verified safe**
  for this image, so it's left off per the no-guessing rule.
- **`/data` is read-only** — Jellyfin never writes to your media. If you later
  use Jellyfin features that write back (e.g. saving `.nfo` metadata next to
  files), drop `read_only: true` on that mount.
- **Reverse proxy:** if fronting with Caddy, switch the port line to
  `127.0.0.1:8096:8096` and join the shared `proxy` network instead.
- **DLNA / client auto-discovery** needs host networking, which this bridge
  setup does not provide. Access by IP/URL works fine; only LAN
  auto-discovery is affected.
- **Hardware transcoding is not configured.** On an ARM Raspberry Pi there is no
  Intel/AMD VAAPI; Pi GPU transcoding in Jellyfin is a separate, unverified setup,
  so it's left off until actually tested. Software transcoding works as-is.

---
_Tested on: `raspberrypi` (Pi 4 Model B, 3.7 GiB), 2026-06-26 — `docker compose
up -d` brings Jellyfin up healthy under the tightened baseline (`cap_drop: ALL`
+ `no-new-privileges`) and it reads the read-only NTFS media at `/data`.
Remaining: first-run wizard + library scan (Web UI), and `mem_limit` is discarded
until the memory cgroup is enabled (see Notes)._
