# Docker

One place for every Docker container I run, with a single standard for how each
one is organized, stored, secured, and upgraded. Follow these rules for every new
container — no exceptions, no snowflakes.

New host? Start with [docs/host-setup.md](docs/host-setup.md), then deploy any
container below.

> ## ⚠️ Only tested commands
> Nothing goes into this repo until it has been **run on the real host and worked**.
> No guessing, no "should work." Every command in a container README is copied from
> an actual successful run. Anything not yet verified is marked `⚠️ UNTESTED` or left
> out entirely. Each container README ends with a **Tested on** line recording the
> host + date its commands were last verified.

## Containers

| Container | Purpose | Image | Port | Storage |
|-----------|---------|-------|------|---------|
| [netbird](containers/netbird) | WireGuard mesh VPN client | `netbirdio/netbird:latest` | — | `netbird-client` (volume) |
| [atvloadly](containers/atvloadly) | Apple TV IPA sideloading | `bitxeno/atvloadly:latest` | 5533 | `/etc/atvloadly` (bind) |

> Keep this table updated whenever you add or remove a container.

## Adding a new container

1. `cp -r templates containers/<app>` — gives you `docker-compose.yml`, `.env.example`, `README.md`.
2. Fill in the compose file: `image:` (use `:latest`), `container_name`, `hostname`, storage, network.
3. Fill in the README from the template — **keep the section order** (see Style below).
4. Add only the `cap_add` / `devices` the app genuinely needs.
5. Secrets go in `.env` (copy from `.env.example`); confirm `.env` is gitignored.
6. `docker compose up -d`, then check `docker compose ps` + the app's health.
7. Add a row to the **Containers** table above.
8. Commit the folder (compose + README + `.env.example`) — never `.env` or `data/`.

## README style (every container README)

Each `containers/<app>/README.md` is a copy of [templates/README.md](templates/README.md)
and uses this **fixed structure**:

1. `# <Name>` + one-sentence description
2. **At-a-glance table**: Upstream · Image · Web UI · Storage · Network · Host deps
   (always credit/link the original upstream project)
3. `## Prerequisites` → `## Deploy` → `## Upgrade` → `## Verify` → `## Backup` → `## Notes`

Rules: keep it short, link out to deeper docs instead of pasting walls of text,
and record any deliberate deviation from this standard under `## Notes`.

---

## 1. One container = one folder = one compose file

- Every app lives in `containers/<app>/docker-compose.yml`.
- Folder name = compose project name = lowercase app name (`netbird`, `atvloadly`).
- No `docker run` for anything permanent. If it should survive a reboot, it's a compose file.
- On the host, containers live under a single root: `~/docker/<app>/` (or `/opt/containers/<app>/`).

## 2. Naming — be explicit, never rely on defaults

| Thing            | Rule                                   | Example                    |
|------------------|----------------------------------------|----------------------------|
| Folder           | lowercase app name                     | `containers/netbird`       |
| `container_name` | = app name                             | `NetBird`                  |
| Named volume     | `<app>-<purpose>`                      | `netbird-client`           |
| Network          | `<app>_net`, or shared `proxy`         | `atvloadly_net`            |
| Image            | use `:latest`; `pull` to upgrade       | `netbirdio/netbird:latest` |

## 3. Storage — data is never inside the container

Two allowed patterns. Pick one per container and document it.

**A. Bind mount (default — clear path, easy backup):**
```yaml
volumes:
  - ./data:/var/lib/app      # data sits right next to the compose file
```
Everything is visible at `~/docker/<app>/data` and trivially backed up with `tar`.

**B. Named volume (when the app is picky about permissions/UID):**
```yaml
volumes:
  - app-data:/var/lib/app
volumes:
  app-data:
    external: true           # reuse an existing volume; don't auto-namespace it
```

Rules:
- New containers default to **bind mounts** (pattern A) for visibility + backup.
- Keep existing named-volume containers as-is (e.g. NetBird) — migrating means re-setup.
- **Never** write data to a path that isn't a mount. Anything not on a mount is lost on upgrade — by design.

## 4. Security baseline (apply to every container)

```yaml
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true   # block privilege escalation
    read_only: true              # if the app tolerates it; add tmpfs for /tmp
    cap_drop:
      - ALL                      # drop everything…
    cap_add:
      - NET_ADMIN                # …then add back ONLY what's needed
    mem_limit: 512m              # cap blast radius
    pids_limit: 200
```

More rules:
- **Always pull latest.** Use `:latest` and run `docker compose pull && docker compose up -d`
  to upgrade. Trade-off: no clean version rollback — if you need to revert, pin to a
  known-good tag (or image digest) temporarily, then go back to `:latest`.
- **Least capability.** Start from `cap_drop: ALL`, add only the specific caps the app needs.
- **Bind ports to localhost** when an app sits behind a reverse proxy:
  `ports: ["127.0.0.1:5533:80"]` — not reachable from the LAN directly.
- **Secrets live in `.env`**, never in the compose file, never committed. Commit `.env.example` only.
- **Run as non-root** where the image supports it: `user: "1000:1000"` or `PUID/PGID` env.
- Keep the host patched; review `docker scout` / image CVEs before pinning a new tag.

## 5. Networks

- Each container gets its **own** bridge network (`<app>_net`) for isolation by default.
- Apps that must talk to a reverse proxy join a **shared external** network named `proxy`.
- Only publish ports you actually need; everything internal stays on the bridge.

Create the shared proxy network once per host:
```bash
docker network create proxy
```

## 6. Upgrades — always the same two commands

```bash
cd ~/docker/<app>
docker compose pull && docker compose up -d
```
- `up -d` recreates the container only if the image changed; volumes are never touched.
- **Never** `docker compose down -v` (the `-v` deletes volumes). Plain `down` / `up -d` are safe.
- Images use `:latest`, so `pull` always fetches the newest build.
- Verify after: `docker compose ps` + the app's own status/health check.
- Reclaim space occasionally: `docker image prune` (safe — never removes volumes).
- Update everything at once: [`scripts/update-all.sh`](scripts/update-all.sh).

## 7. Backup before risky changes

```bash
# named volume:
docker run --rm -v <vol>:/data -v "$PWD":/backup alpine \
  tar czf /backup/<app>-$(date +%F).tar.gz -C /data .

# bind mount:
tar czf <app>-$(date +%F).tar.gz -C ~/docker/<app>/data .
```

## Repo layout

```
docker/
├── README.md                  # this file — the standard + container index
├── .gitignore                 # never commit secrets/data
├── docs/
│   └── host-setup.md          # one-time host prep (Docker engine, proxy net)
├── templates/                 # copy these to start a new container
│   ├── docker-compose.yml
│   ├── .env.example
│   └── README.md
├── containers/                # one folder per app
│   ├── netbird/
│   └── atvloadly/
└── scripts/
    └── update-all.sh          # pull+up every container
```
