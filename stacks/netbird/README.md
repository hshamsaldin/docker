# NetBird (client / peer)

WireGuard-based mesh VPN client. Registers this Raspberry Pi as a NetBird peer.

- **Image:** `netbirdio/netbird` (pinned in compose)
- **Storage:** external named volume `netbird-client` -> `/var/lib/netbird`
  (holds peer keys + registration; do **not** recreate it or you must re-register)
- **Caps:** `NET_ADMIN` + `/dev/net/tun` device — required for the WireGuard interface

## First-time setup (fresh volume only)

Add a setup key for the very first registration, then remove it:

```yaml
    environment:
      - NB_SETUP_KEY=<your-setup-key>
```

Once registered, credentials live in the volume — the key is no longer needed.

## Deploy / upgrade

```bash
cd ~/docker/netbird
docker compose pull && docker compose up -d   # or bump the pinned tag first
```

## Verify

```bash
docker exec NetBird netbird status | grep -E 'Management|Signal|version'
```

Expect `Management: Connected` and `Signal: Connected`.

## Backup the registration state

```bash
docker run --rm -v netbird-client:/data -v "$PWD":/backup alpine \
  tar czf /backup/netbird-$(date +%F).tar.gz -C /data .
```
