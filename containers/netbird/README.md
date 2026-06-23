# NetBird

WireGuard-based mesh VPN client — registers this host as a NetBird peer.

|              |                                              |
|--------------|----------------------------------------------|
| **Image**    | `netbirdio/netbird:latest`                   |
| **Web UI**   | `—` (CLI: `docker exec NetBird netbird status`) |
| **Storage**  | `netbird-client` (named volume) → `/var/lib/netbird` |
| **Network**  | default bridge (no published ports) + `NET_ADMIN` / `/dev/net/tun` |
| **Host deps**| `—`                                          |

## Prerequisites

- Docker engine — see [host setup](../../docs/host-setup.md).
- **First registration only:** a NetBird setup key. Add it for the very first
  start of a fresh volume, then remove it:
  ```yaml
      environment:
        - NB_SETUP_KEY=<your-setup-key>
  ```
  Once registered, credentials live in the volume — the key is no longer needed.

## Deploy

```bash
cd ~/docker/netbird
docker compose up -d
```

## Upgrade

```bash
cd ~/docker/netbird
docker compose pull
docker compose up -d
```

Real output from an upgrade run:

```
[+] pull 6/6
 ✔ Image netbirdio/netbird:latest Pulled
[+] up 1/1
 ✔ Container NetBird Started
```

## Verify

Use the container name so it works from **any** directory:

```bash
docker exec NetBird netbird status
```

```
Management: Connected
Signal: Connected
Relays: 4/4 Available
FQDN: pi.netbird.cloud
NetBird IP: 100.125.193.30/16
Wireguard port: 51820
Peers count: 2/3 Connected
```

Quick version check:

```bash
docker exec NetBird netbird status | grep -E 'Daemon version|CLI version'
```

```
Daemon version: 0.73.2
CLI version: 0.73.2
```

Confirm the data volume is attached:

```bash
docker inspect -f '{{range .Mounts}}{{.Name}} -> {{.Destination}}{{println}}{{end}}' NetBird
```

```
netbird-client -> /var/lib/netbird
```

> ⚠️ `docker compose exec netbird netbird status` only works **from inside
> `~/docker/netbird`** — run elsewhere it fails with
> `no configuration file provided: not found`. Use the `docker exec NetBird …`
> form above to avoid that.

## Backup

⚠️ UNTESTED — the registration state (peer keys + session) lives in the
`netbird-client` volume; this is the intended backup command but hasn't been
run yet on this host:

```bash
docker run --rm -v netbird-client:/data -v "$PWD":/backup alpine \
  tar czf /backup/netbird-$(date +%F).tar.gz -C /data .
```

## Notes

- Uses an **external** named volume (`external: true`) — recreating the container
  reuses the existing registration; do **not** delete the volume or you must
  re-register with a new setup key.
- Keeps `NET_ADMIN` + `/dev/net/tun` (required for the WireGuard interface).

---
_Tested on: `raspberrypi` (linux/arm64), `2026-06-23` — deploy, upgrade, and all
verify commands run and confirmed. Backup marked UNTESTED above._
