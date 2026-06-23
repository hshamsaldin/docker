#!/usr/bin/env bash
# Pull newer images and recreate every stack. Volumes are never touched.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../containers" && pwd)"

for dir in "$ROOT"/*/; do
  [ -f "$dir/docker-compose.yml" ] || continue
  echo "==> Updating $(basename "$dir")"
  docker compose -f "$dir/docker-compose.yml" pull
  docker compose -f "$dir/docker-compose.yml" up -d
done

echo "==> Pruning dangling images"
docker image prune -f

echo "==> Done."
