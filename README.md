# Docker Standards

How every container on my hosts is organized, stored, secured, and upgraded.
Follow these rules for every new stack — no exceptions, no snowflakes.

## 1. One stack = one folder = one compose file

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
| Image            | **always pinned**, never bare `latest` | `netbirdio/netbird:0.73.2` |

## 3. Storage — data is never inside the container

Two allowed patterns. Pick one per stack and document it.

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
- New stacks default to **bind mounts** (pattern A) for visibility + backup.
- Keep existing named-volume stacks as-is (e.g. NetBird) — migrating means re-setup.
- **Never** write data to a path that isn't a mount. Anything not on a mount is lost on upgrade — by design.

## 4. Security baseline (apply to every stack)

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
- **Pin image versions.** Upgrades become deliberate, rollback = change the tag back.
- **Least capability.** Start from `cap_drop: ALL`, add only the specific caps the app needs.
- **Bind ports to localhost** when an app sits behind a reverse proxy:
  `ports: ["127.0.0.1:5533:80"]` — not reachable from the LAN directly.
- **Secrets live in `.env`**, never in the compose file, never committed. Commit `.env.example` only.
- **Run as non-root** where the image supports it: `user: "1000:1000"` or `PUID/PGID` env.
- Keep the host patched; review `docker scout` / image CVEs before pinning a new tag.

## 5. Networks

- Each stack gets its **own** bridge network (`<app>_net`) for isolation by default.
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
- For pinned versions: bump the tag in `docker-compose.yml`, then run the two commands.
- Verify after: `docker compose ps` + the app's own status/health check.
- Reclaim space occasionally: `docker image prune` (safe — never removes volumes).

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
├── README.md                  # this file — the standard
├── .gitignore                 # never commit secrets/data
├── templates/
│   ├── docker-compose.yml     # copy to start any new stack
│   └── .env.example
├── containers/                # one folder per app
│   ├── netbird/
│   └── atvloadly/
└── scripts/
    └── update-all.sh          # pull+up every container
```

## Starting a new stack (checklist)

1. `cp -r templates containers/<app>` then rename `templates` content into place.
2. Set `image:` to a **pinned** version, `container_name`, `hostname`.
3. Choose storage: bind mount `./data` (default) or external named volume.
4. Add only the `cap_add` / `devices` the app genuinely needs.
5. Put secrets in `.env` (copy from `.env.example`); confirm `.env` is gitignored.
6. `docker compose up -d`, then check `docker compose ps` + the app's health.
7. Commit the stack folder (compose + README + `.env.example`) — never `.env` or `data/`.
