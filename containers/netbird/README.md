# NetBird

WireGuard-based mesh VPN client — registers this host as a NetBird peer.

|              |                                              |
|--------------|----------------------------------------------|
| **Image**    | `netbirdio/netbird:latest`                   |
| **Web UI**   | `—` (CLI: `netbird status`)                  |
| **Storage**  | `netbird-client` (named volume) → `/var/lib/netbird` |
| **Network**  | `host` (uses `NET_ADMIN` + `/dev/net/tun`)   |
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
docker compose pull && docker compose up -d
```

## Verify

```bash
docker exec NetBird netbird status | grep -E 'Management|Signal|version'
```

Expect `Management: Connected` and `Signal: Connected`.

## Backup

The registration state (peer keys + session) lives in the `netbird-client` volume:

```bash
docker run --rm -v netbird-client:/data -v "$PWD":/backup alpine \
  tar czf /backup/netbird-$(date +%F).tar.gz -C /data .
```

## Notes

- Uses an **external** named volume (`external: true`) — recreating the container
  reuses the existing registration; do **not** delete the volume or you must
  re-register with a new setup key.
- Keeps `NET_ADMIN` + `/dev/net/tun` (required for the WireGuard interface); this
  is the minimal capability set, not a deviation.
