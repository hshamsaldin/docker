# Host setup (one-time, per machine)

Do this once on a fresh host before deploying any container from this repo.

## 1. Install Docker Engine

(Debian / Raspberry Pi OS — adjust the distro path for others.)

```bash
# remove conflicting packages
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt remove -y "$pkg" 2>/dev/null || true
done

# add Docker's official repo
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

# install
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

## 2. Run Docker without sudo (optional)

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

## 3. Create the shared proxy network (once)

Only needed if you run containers behind a reverse proxy (see the standard, §5).

```bash
docker network create proxy
```

## 4. Pick a stacks root

All containers live under one directory on the host — keep it consistent:

```bash
mkdir -p ~/docker        # or /opt/containers
```

Each container then lives at `~/docker/<app>/` with its own `docker-compose.yml`.
