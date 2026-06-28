# qBittorrent (via gluetun / ProtonVPN)

BitTorrent client whose traffic is forced entirely through a ProtonVPN
WireGuard tunnel — if the VPN drops, qBittorrent has no network (kill switch).

|              |                                          |
|--------------|------------------------------------------|
| **Upstream** | [linuxserver/qbittorrent](https://github.com/linuxserver/docker-qbittorrent) · [qdm12/gluetun](https://github.com/qdm12/gluetun) (→ [passteque/gluetun](https://github.com/passteque/gluetun)) |
| **Image**    | `lscr.io/linuxserver/qbittorrent:latest` · `qmcgaw/gluetun:latest` |
| **Web UI**   | `http://<host>:8080` (qBittorrent, published *on gluetun*) |
| **Storage**  | `./config`, `./gluetun`, `./scripts` (bind) · downloads disk → `/downloads` (bind) |
| **Network**  | qBittorrent runs in **gluetun's** netns (`network_mode: service:gluetun`); only gluetun publishes ports |
| **Host deps**| `/dev/net/tun` (kernel tun device — present by default on Linux) |

## Prerequisites

- Docker engine + compose plugin — see [host setup](../../docs/host-setup.md).
- A **ProtonVPN** account with a **WireGuard** config:
  Proton portal → *Downloads → WireGuard configuration* → choose a **P2P**
  server, enable **Moderate NAT**, generate, and copy the `PrivateKey` line into
  `.env` as `WIREGUARD_PRIVATE_KEY`.
- A downloads location on the host for `DOWNLOADS_PATH` (its own disk, or a
  folder on the media disk mounted per the [jellyfin](../jellyfin) fstab steps).
- `/dev/net/tun` must exist on the host (`ls -l /dev/net/tun`). It's standard on
  Linux; if missing, `sudo modprobe tun`.

## Deploy

Copy `docker-compose.yml` and `.env.example` from this folder
(`containers/qbittorrent/`) onto the host, then bring it up:

```bash
mkdir -p ~/docker/qbittorrent && cd ~/docker/qbittorrent
# place this folder's docker-compose.yml and .env.example here first
cp .env.example .env                   # then edit the WireGuard key, PUID/PGID, paths

# config must be writable by PUID:PGID, or the s6 init crash-loops. Create it
# owned by your user first (Docker would otherwise auto-create it root-owned):
mkdir -p config gluetun
sudo chown -R "$(id -u):$(id -g)" config

docker compose up -d
```

The first WebUI login is `admin` + a **temporary password printed in the logs**:

```bash
docker compose logs qbittorrent | grep -i password
```

Open `http://<host>:8080`, log in, change the password, and set the save path to
`/downloads` (e.g. `/downloads/complete`).

## Upgrade

```bash
cd ~/docker/qbittorrent
docker compose pull && docker compose up -d
```

## Verify

```bash
docker compose ps                      # both services "running"; gluetun "healthy"

# Confirm qBittorrent's traffic actually exits via the VPN — this prints the
# ProtonVPN exit IP (NOT your home IP). If it shows your real IP, STOP.
docker compose exec qbittorrent wget -qO- https://ipinfo.io/ip

# Kill-switch check: stop gluetun, then qBittorrent should have NO network.
docker compose stop gluetun
docker compose exec qbittorrent wget -qO- https://ipinfo.io/ip   # must FAIL/hang
docker compose start gluetun
```

## Backup

```bash
# bind mount — tar the qBittorrent config (downloads are not backed up here):
tar czf qbittorrent-$(date +%F).tar.gz -C ~/docker/qbittorrent/config .
```

## Notes

- **Two services, one folder.** Deviation from "one container = one compose":
  gluetun is qBittorrent's inseparable VPN sidecar, so they share this folder
  and compose file. Folder/app name is `qbittorrent`; gluetun is infrastructure
  for it.
- **The kill switch is the whole point.** `network_mode: "service:gluetun"`
  means qBittorrent has no network stack of its own. There is no
  `ports:`/`networks:`/`hostname:` on the qBittorrent service — those live on
  gluetun. Always do the **Verify** IP check after any change; a config slip
  that detaches qBittorrent from gluetun's netns would leak your real IP.
- **WebUI is published on gluetun.** Reaching it from the LAN also needs
  `FIREWALL_OUTBOUND_SUBNETS=${LAN_SUBNET}` (set in `.env`) so gluetun doesn't
  drop the return packets. If the WebUI is unreachable from other machines,
  that subnet is the first thing to check.
- **Port forwarding is auto-wired into qBittorrent.** On each port assign/renew,
  gluetun runs `scripts/qbt-port.sh` (mounted at `/scripts`, via
  `VPN_PORT_FORWARDING_UP_COMMAND`), which POSTs the new port to qBittorrent's
  WebUI API on `127.0.0.1:8080` (same netns), retrying for up to 5 min so it
  rides out a slow qBittorrent startup. This only works because gluetun's
  port-forwarding service no longer aborts (it needs `DAC_OVERRIDE` + `CHOWN`,
  see below) — otherwise the up-command never fires. **One-time setup required:**
  qBittorrent → Settings → Web UI, tick **"Bypass authentication for clients on
  localhost"** so the script needs no login, and untick **"Use UPnP/NAT-PMP"**
  under Connection. Verify with `docker compose exec gluetun cat /tmp/gluetun/forwarded_port`
  vs qBittorrent's listening port.
- **Security-baseline deviations** (deliberate, like `omada`):
  - gluetun keeps `cap_drop: ALL` but **adds `NET_ADMIN`** and the `/dev/net/tun`
    device (mandatory for WireGuard), plus **`DAC_OVERRIDE`** and **`CHOWN`**:
    gluetun's port-forwarding service writes a runtime port file under
    `/tmp/gluetun` (needs `DAC_OVERRIDE` — the dir is mode `0644`, no exec bit)
    and then `chown`s it (needs `CHOWN`). Missing either aborts the PF service
    (`permission denied` / `chown ... operation not permitted`), so it never
    obtains/publishes a port and the up-command never runs.
  - qBittorrent is a linuxserver/s6 image; `cap_drop: ALL` and `read_only` are
    **not** applied (unverified against this image's init, and would risk a
    crash-loop). `no-new-privileges` is kept on both.
  - `mem_limit` (256m gluetun / 1g qBittorrent) is **enforced on this host** —
    the memory cgroup was enabled by appending `cgroup_enable=memory
    cgroup_memory=1` to the single line in `/boot/firmware/cmdline.txt` and
    rebooting (a host-wide change that also activates Jellyfin's limit). Without
    that, a Pi reports `Limitation discarded` and `docker stats` shows `0B`.
    Containers must be **recreated** (`docker compose up -d --force-recreate`)
    after enabling it to actually pick up the limit.
- **Reverse proxy:** set `WEBUI_BIND=127.0.0.1:8080` in `.env` and front gluetun
  with your proxy; the qBittorrent WebUI lives in gluetun's netns.

---
_Tested on: `raspberrypi` (Pi 4 Model B), 2026-06-28 — `docker compose up -d`
brings **gluetun up healthy** and qBittorrent in its netns; the leak check
returns a **Swiss ProtonVPN exit IP** (country `CH`), no leak. DNS via Cloudflare
DoT resolves trackers reliably (Quad9 DoT was reset on this route). **`mem_limit`
enforced** (`146MiB/256MiB` gluetun, `24MiB/1GiB` qbit) once the memory cgroup was
enabled + containers recreated (see Notes). **Auto port-forwarding verified
end-to-end:** with `DAC_OVERRIDE` + `CHOWN` the PF service no longer aborts, so
gluetun's up-command runs `qbt-port.sh` on each port assign — confirmed by
planting a wrong port (`12345`) and watching it auto-correct to the forwarded
port (`36409`) with no manual action (gluetun logs `qbt-port: set ... to 36409`).
Remaining optional check: the stop-gluetun **kill-switch** test under Verify._
