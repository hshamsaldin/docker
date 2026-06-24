# Omada

TP-Link Omada SDN controller — manages the EAP APs, switches, and gateway. It is
a **control plane only**: APs/switches keep forwarding and the internet stays up
even while this container is stopped.

|              |                                          |
|--------------|------------------------------------------|
| **Upstream** | [mbentley/docker-omada-controller](https://github.com/mbentley/docker-omada-controller) |
| **Image**    | `mbentley/omada-controller:latest`       |
| **Web UI**   | `https://<host>:8043` (self-signed cert) |
| **Storage**  | `omada-data` / `omada-logs` (external named volumes) → `/opt/tplink/EAPController/{data,logs}` |
| **Network**  | `bridge` — ports published LAN-wide (devices must reach them) |
| **Host deps**| `—`                                      |

## Prerequisites

- Docker engine — see [host setup](../../docs/host-setup.md).
- The external volumes must already exist (they do on this host: `hussein_omada-data`,
  `hussein_omada-logs`). Compose reuses them via `external: true`; it will **not**
  create them. A blank volume comes up as a brand-new, empty controller.

## Deploy

```bash
cd ~/docker/omada
docker compose up -d
```

> ⚠️ UNTESTED — the controller is currently running from an older container
> created outside this repo. To switch it to this compose file, remove the old
> container first (data is safe on the external volume): `docker stop Omada && docker rm Omada`.

## Upgrade

```bash
cd ~/docker/omada
docker compose pull && docker compose up -d
```

> ⚠️ UNTESTED + **major-version jump.** This host is on **5.13.30**; `:latest` is
> now **6.x**. Do **not** leap 5.13 → 6.x in one pull — step through a late `5.x`
> tag first, let the DB migration finish, then go to `:latest`. Back up the volume
> (below) before each step; a migrated DB cannot be downgraded in place.

## Verify

```bash
docker compose ps
# UI: https://<host>:8043  (accept the self-signed cert)
# devices reconnect as Connected/Provisioned within ~2 min
```

## Backup

Two layers — do both before any upgrade:

1. **In-app export** (portable, version-safe): Global view → Settings → Maintenance
   → Backup & Restore → Export → `.cfg`.
2. **Volume snapshot** (instant rollback):

```bash
docker run --rm -v hussein_omada-data:/data -v "$PWD":/backup alpine \
  tar czf /backup/omada-$(date +%F).tar.gz -C /data .
```

> ⚠️ UNTESTED — derived from the standard volume-backup pattern; not yet run on this host.

## Notes

- **External named volumes** (`external: true`): recreating the container reuses the
  existing controller state. Never `docker compose down -v`, and never delete
  `hussein_omada-data`, or you lose all sites/devices.
- **Security-baseline deviations** (deliberate, like `atvloadly`): `cap_drop: ALL`,
  `read_only`, `no-new-privileges`, and `mem_limit: 512m` are intentionally **omitted** —
  the controller runs MongoDB + a JVM and needs well over 512 MB, and tightening caps
  against this image is unverified. Mirrors mbentley's proven upstream config instead.
- **Ports are LAN-wide, not localhost-bound:** APs/switches/gateway adopt and inform
  over `8043`/`29810-29817`/etc., so they cannot sit behind a localhost-only bind.
- Login is **HTTPS on 8043**. `8843` is the guest portal (no `/login` there → 404).

---
_⚠️ UNTESTED on this host. Compose is derived from `docker inspect` of the live,
healthy `5.13.30` container, but has not yet been re-applied via `docker compose`,
and the major-version upgrade is unverified. Replace this line with
`Tested on: <host>, <YYYY-MM-DD>` once deploy + upgrade have actually been run._
