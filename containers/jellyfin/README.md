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

### USB disk dropping off under load? (UAS quirk)

On a Raspberry Pi, many USB‑SATA/NVMe bridges (Realtek RTL9210, JMicron, some
ASMedia) ship **buggy UAS** (USB Attached SCSI) firmware that crashes the USB
controller under sustained I/O — exactly what a media server + downloads cause.
The drive vanishes mid-use and `/data` silently falls back to the SD card; your
libraries/downloads look "missing" until the disk is remounted. Tell-tale signs
in `dmesg`:

```
sd 0:0:0:0: [sda] ... uas_eh_abort_handler ...
xhci_hcd 0000:01:00.0: xHCI host controller not responding, assume dead
xhci_hcd 0000:01:00.0: HC died; cleaning up
```

**Fix — force the stable `usb-storage` driver for that one bridge:**

1. Find *your* bridge's USB ID (don't copy another host's — discover this one's):
   ```bash
   lsusb     # e.g. "Bus 002 ... ID 0bda:9210 Realtek ... RTL9210B-CG"
   ```
2. Append `usb-storage.quirks=<vid>:<pid>:u` to the **single line** in
   `/boot/firmware/cmdline.txt` (`:u` = ignore UAS), keeping it one line:
   ```bash
   sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak
   grep -q usb-storage.quirks /boot/firmware/cmdline.txt || \
     sudo sed -i 's/$/ usb-storage.quirks=<vid>:<pid>:u/' /boot/firmware/cmdline.txt   # e.g. 0bda:9210:u
   sudo reboot
   ```
3. Confirm after reboot — the bridge should now use `usb-storage`, not `uas`:
   ```bash
   dmesg | grep -iE 'UAS is ignored|Quirks match|usb-storage'
   # -> "UAS is ignored for this device, using usb-storage instead"
   # -> "Quirks match for vid <vid> pid <pid>"
   ```

Trade-off: slightly lower sequential throughput (no command queuing), but
rock-solid — and still well above the Pi's 1 GbE bottleneck. It affects **only**
the listed bridge; other USB drives keep using UAS. This also fixes the same disk
for any other container on `/data` (e.g. [qbittorrent](../qbittorrent)).

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
script (it reads a **local path**, so the zip must already be there).

Copy the zip from Windows (PowerShell), substituting your own user/IP — land it at
`/tmp/subtitles.zip` to match the script's default prompt:
```powershell
scp "C:\Users\<user>\Downloads\subtitles.zip" <user>@<pi-ip>:/tmp/subtitles.zip
# e.g.  scp "C:\Users\user\Downloads\got-s06.zip" pi@192.168.1.50:/tmp/subtitles.zip
```
If you scp it somewhere else (or under a different name), just type that path at the
script's `Subtitles .zip or folder` prompt instead of accepting `/tmp/subtitles.zip`.

Install once — keep the script under your jellyfin deploy dir so it reads the
**same `.env`** as the compose:
```bash
cp -r scripts ~/docker/jellyfin/                       # -> ~/docker/jellyfin/scripts/
chmod +x ~/docker/jellyfin/scripts/ManageSubtitles.sh
# optional: run it from anywhere (the symlink is resolved, still finds ../.env)
sudo ln -sf ~/docker/jellyfin/scripts/ManageSubtitles.sh /usr/local/bin/ManageSubtitles.sh
```

Then run it — no options:
```bash
~/docker/jellyfin/scripts/ManageSubtitles.sh      # or just: ManageSubtitles.sh  (if symlinked)
```
and answer the prompts:
```
Shows under /data/jellyfin/Shows:
  1- Game of Thrones
Show (number or name): 1
Seasons in Game of Thrones:
  0- All seasons
  1- Season 01
  2- Season 02
  3- Season 03
  4- Season 04
  5- Season 05
  6- Season 06
  7- Season 07
  8- Season 08
Season (number or name) [0=all]: 6
Subtitles .zip or folder [/tmp/subtitles.zip]: /tmp/subtitles.zip
Language tag [ara]:
----- preview -----
S06E01  Game.of.Thrones.S06E01...srt  ->  Game.Of.Thrones.S06E01.BluRay.4K.UHD.H265.ara.srt
...
DRY-RUN  matched=10  missing=0
Applies to: Season 06
Apply (place + archive + flatten)? [y/N] y
APPLIED  matched=10  missing=0
API key:  Jellyfin Dashboard -> Advanced -> API Keys -> +   (grey hint)
Jellyfin API key for auto-scan: <paste, or blank to skip>
scan: HTTP 204
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

To skip the prompt every time, put the key in your deploy `.env` — the **same
`~/docker/jellyfin/.env`** as the compose (the script reads it from one level up):
```bash
# in ~/docker/jellyfin/.env  (copied from .env.example):
JELLYFIN_API_KEY=<your-key>          # optional: JELLYFIN_URL, JELLYFIN_SHOWS
```
The script loads it on start and auto-scans after import. `.env` is gitignored —
never commit it; only `.env.example` lives in the repo.

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
`scripts/ManageSubtitles.sh` verified 2026-06-27: show/season menus, default
`/tmp/subtitles.zip`, placed S04/S05/S06 Arabic subs beside the episodes +
archived under `Subtitles/`, flattened the doubled season folder, and the API
scan (`POST /Library/Refresh`) returned `HTTP 204`.
Remaining: first-run wizard + library scan (Web UI), and `mem_limit` is discarded
until the memory cgroup is enabled (see Notes)._
