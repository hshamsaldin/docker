# atvloadly

Web tool for sideloading apps to Apple TV / iOS devices.

- **Image:** `bitxeno/atvloadly` — **TODO: pin a version tag** (currently `:latest`)
- **Web UI:** http://<host>:5533
- **Storage:** `./data` bind mount — **TODO: confirm the real internal data path**
  Run `docker inspect atvloadly` and check the existing `Mounts` to set this correctly
  before relying on it, or config may live in an unmounted path and be lost on upgrade.

## Deploy / upgrade

```bash
cd ~/docker/atvloadly
docker compose pull && docker compose up -d
```

## Verify

```bash
docker compose ps
curl -sI http://localhost:5533 | head -1
```
