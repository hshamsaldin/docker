#!/bin/bash
# Wakes the Apple TV via pyatv if it's asleep. Run as ExecStartPre by
# atvloadly-refresh.service, before atvloadly-refresh.sh - a refresh queued
# against a sleeping Apple TV silently fails.
set -uo pipefail

ATV_IP="<atv-ip>"
ATV_ID="<atv-id>"              # pyatv identifier, not the ARP/router MAC - see README
ATV_REMOTE="/home/YOUR_USER/atvloadly/pyatv-venv/bin/atvremote"

STATE=$("$ATV_REMOTE" --scan-hosts "$ATV_IP" --id "$ATV_ID" power_state | xargs)

if [ "$STATE" != "PowerState.On" ]; then
    echo "Apple TV is off ($STATE). Turning on..."
    "$ATV_REMOTE" --scan-hosts "$ATV_IP" --id "$ATV_ID" turn_on
    sleep 25
else
    echo "Apple TV is already on."
fi
