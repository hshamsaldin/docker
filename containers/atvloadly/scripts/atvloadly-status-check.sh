#!/bin/bash
set -euo pipefail
BASE="http://localhost:5533"
LOG="$HOME/atvloadly-status-check.log"

REPORT=$(curl -s "$BASE/api/apps" | python3 -c '
import json, sys

data = json.load(sys.stdin)["data"]
ok = sum(1 for a in data if a.get("refreshed_result"))
fail = len(data) - ok

lines = []
for a in data:
    name = a.get("ipa_name", "?")
    if a.get("refreshed_result"):
        lines.append(name + ": OK exp=" + str(a.get("expiration_date")))
    else:
        lines.append(name + ": FAIL(err=" + str(a.get("refreshed_error")) + ") last_refresh=" + str(a.get("refreshed_date")))

print(fail)
print("atvloadly status: " + str(ok) + " ok / " + str(fail) + " failed")
print(" | ".join(lines))
')

FAIL=$(echo  "$REPORT" | sed -n '1p')
TITLE=$(echo "$REPORT" | sed -n '2p')
BODY=$(echo  "$REPORT" | sed -n '3p')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Notify only when at least one app failed to refresh.
if [ "$FAIL" -gt 0 ]; then
    ENC_TITLE=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$TITLE")
    ENC_BODY=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$BODY")
    curl -s "$BASE/api/notify/send?title=$ENC_TITLE&desc=$ENC_BODY" > /dev/null
    echo "[$TIMESTAMP] NOTIFIED (fail=$FAIL) - $TITLE | $BODY" >> "$LOG"
else
    echo "[$TIMESTAMP] OK, no failures - not notifying - $TITLE" >> "$LOG"
fi

echo "$TITLE"
echo "$BODY"
