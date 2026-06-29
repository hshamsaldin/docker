# Omada

TP-Link Omada SDN controller — manages the EAP APs, switches, and gateway. It is
a **control plane only**: APs/switches keep forwarding and the internet stays up
even while this container is stopped.

|              |                                          |
|--------------|------------------------------------------|
| **Upstream** | [mbentley/docker-omada-controller](https://github.com/mbentley/docker-omada-controller) |
| **Image**    | `mbentley/omada-controller:6.2` (pinned — see Notes) |
| **Web UI**   | `https://<host>:8043` (self-signed cert) |
| **Storage**  | `omada-data` / `omada-logs` (external named volumes) → `/opt/tplink/EAPController/{data,logs}` |
| **Network**  | `bridge` — ports published LAN-wide (devices must reach them) |
| **Host deps**| `—`                                      |

## Prerequisites

- Docker engine — see [host setup](../../docs/host-setup.md).
- The external volumes must already exist (`hussein_omada-data`, `hussein_omada-logs`).
  Compose reuses them via `external: true`; it will **not** create them. A blank
  volume comes up as a brand-new, empty controller.
- CPU with **AVX** (x86_64) — required by MongoDB 5+, which 6.x bundles.

## Deploy

```bash
cd ~/docker/omada
docker compose up -d
```

If switching from an old container created outside this repo, remove it first
(data is safe on the external volume): `docker stop Omada && docker rm Omada`.

## Upgrade

Within the same major line (e.g. 6.2.x patch bumps), it's the standard two commands:

```bash
cd ~/docker/omada
docker compose pull && docker compose up -d
```

> **Crossing 5.x → 6.x is NOT a plain `pull`.** 6.x ships MongoDB 8, but 5.x data is
> on an ancient MongoDB (WiredTiger 3.1.0); 6.x refuses to start until the database is
> converted. The verified path that worked on this host:
>
> 1. Back up first (see Backup) — `.cfg` export **and** a volume snapshot.
> 2. Step the app to the last 5.x so its own schema is current:
>    `image: …:5.15` → `docker compose pull && up -d` → confirm healthy.
> 3. Stop the controller, then run mbentley's MongoDB upgrade container (steps
>    Mongo 3.6 → 8.0 automatically, makes its own internal backup):
>    ```bash
>    docker compose stop
>    docker run -it --rm -e DEBUG=false \
>      -v hussein_omada-data:/opt/tplink/EAPController/data \
>      mbentley/omada-controller:mongodb-upgrade-3.6-to-8
>    ```
> 4. Move the app up: `image: …:6.0` → `up -d` (does the 5.15→6.0 app migration),
>    then `image: …:6.2` → `up -d`. **Do not** point at `:latest` (see Notes).

## Verify

```bash
docker compose ps
docker exec Omada ls /opt/tplink/EAPController/lib | grep -i omada-common   # shows running version
# UI: https://<host>:8043  (accept the self-signed cert)
# devices reconnect as Connected/Provisioned within ~2 min
```

## Backup

Two layers — do both before any upgrade:

1. **In-app export** (portable, version-safe): Global view → Settings → Maintenance
   → Backup & Restore → Export → `.cfg`.
2. **Volume snapshot** (instant rollback). Stop the container and skip gzip — on a
   large DB `tar czf` of a live volume can crawl/appear to hang:

```bash
docker compose stop
docker run --rm -v hussein_omada-data:/data -v "$PWD":/backup alpine \
  tar cf /backup/omada-$(date +%F).tar -C /data .
docker compose start
```

Tip: enable **Auto Backup** in the UI (Settings → Maintenance) so you're not doing
this by hand each time.

## Notes

- **Pinned to `6.2`, not `:latest` — important.** mbentley's `:latest` tag tracks the
  **5.x** line (so naive `pull` users don't get auto-broken by the 6.x MongoDB upgrade).
  Pointing this container at `:latest` after you're on 6.x pulls a 5.15 image, which the
  entrypoint **refuses to start** ("version from image is older than last version executed").
  Bump the pin deliberately (`6.2` → future `6.3`/`7.x`) when you choose to.
- **External named volumes** (`external: true`): recreating the container reuses the
  existing controller state. Never `docker compose down -v`, and never delete
  `hussein_omada-data`, or you lose all sites/devices.
- The MongoDB upgrade leaves a `mongodb-preupgrade.tar` inside the data volume as a
  rollback copy; remove it once verified:
  `docker run --rm -v hussein_omada-data:/data alpine rm -f /data/mongodb-preupgrade.tar`.
- **Security-baseline deviations** (deliberate, like `atvloadly`): `cap_drop: ALL`,
  `read_only`, `no-new-privileges`, and `mem_limit: 512m` are intentionally **omitted** —
  the controller runs MongoDB + a JVM and needs well over 512 MB. Mirrors mbentley's
  proven upstream config instead.
- **Ports are LAN-wide, not localhost-bound:** APs/switches/gateway adopt and inform
  over `8043`/`29810-29817`/etc., so they cannot sit behind a localhost-only bind.
- Login is **HTTPS on 8043**. `8843` is the guest portal (no `/login` there → 404).

---
_Tested on: `debian` (x86_64), `2026-06-29` — deploy + full upgrade
`5.13.30 → 5.15 → [MongoDB 3.6→8.0] → 6.0 → 6.2.10.17` run and verified; APs
re-adopted automatically, no data loss. Volume-snapshot backup verified; `.cfg`
export not re-tested this run._
