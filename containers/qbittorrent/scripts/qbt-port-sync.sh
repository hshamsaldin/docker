#!/bin/sh
# Continuously keep qBittorrent's listening port == gluetun's ProtonVPN
# forwarded port. Runs as a sidecar in gluetun's network namespace, so
# qBittorrent's WebUI is reachable on 127.0.0.1:8080 ("Bypass authentication for
# clients on localhost" must be enabled, so no login is needed).
#
# gluetun writes the current forwarded port to /portsync/port on each
# assign/renew (via VPN_PORT_FORWARDING_UP_COMMAND). This loop applies it to
# qBittorrent whenever they differ — surviving slow startups, reconnects,
# reboots, and port changes, which a one-shot up-command cannot.
set -u
API="http://127.0.0.1:8080/api/v2"

while true; do
  if [ -r /portsync/port ]; then
    want=$(tr -dc '0-9' < /portsync/port)
    if [ -n "$want" ]; then
      cur=$(wget -qO- "$API/app/preferences" 2>/dev/null \
              | sed -n 's/.*"listen_port":\([0-9]*\).*/\1/p')
      if [ -n "$cur" ] && [ "$want" != "$cur" ]; then
        if wget -qO- --post-data="json={\"listen_port\":$want}" \
             "$API/app/setPreferences" >/dev/null 2>&1; then
          echo "$(date '+%F %T') port-sync: listen_port $cur -> $want"
        fi
      fi
    fi
  fi
  sleep 30
done
