#!/bin/bash
# ManageSubtitles.sh - interactive subtitle importer for Jellyfin.
#
# Just run it, no arguments:
#     ./ManageSubtitles.sh
# It asks for the show, the subtitles (.zip or folder), and the language, shows a
# preview, and on "y" places each sub beside its episode as <video>.<lang>.<ext>,
# archives a copy in Subtitles/, flattens any "Season NN/Season NN", and can
# trigger a Jellyfin library scan.
#
# Needs python3 (matching) + curl (optional scan). Run on the host (where the
# media and Jellyfin live).
set -uo pipefail
SHOWS="${JELLYFIN_SHOWS:-/data/jellyfin/Shows}"
JELLYFIN_URL="${JELLYFIN_URL:-http://localhost:8096}"

# --- matcher (python, driven by simple positional args: show src lang [apply archive flatten]) ---
PY=$(cat <<'PYEOF'
import sys, os, re, shutil, tempfile, zipfile
VIDEO_EXT=(".mkv",".mp4",".avi",".m4v"); SUB_EXT=(".srt",".ass",".ssa",".vtt",".sub")
CODE=re.compile(r'[Ss](\d{1,2})[ ._-]*[Ee](\d{1,2})')
def codeof(n):
    m=CODE.search(n); return (int(m.group(1)),int(m.group(2))) if m else None
def find(root,exts):
    out=[]
    for d,_,fs in os.walk(root):
        for f in fs:
            if f.lower().endswith(exts): out.append(os.path.join(d,f))
    return out
show, src, lang = sys.argv[1], sys.argv[2], sys.argv[3]
flags=set(sys.argv[4:]); apply="apply" in flags; archive="archive" in flags; flatten="flatten" in flags
if flatten and apply:
    for inner in sorted([d for d,_,_ in os.walk(show)
                         if os.path.basename(d)==os.path.basename(os.path.dirname(d))],
                        key=len, reverse=True):
        parent=os.path.dirname(inner)
        for e in os.listdir(inner): shutil.move(os.path.join(inner,e), os.path.join(parent,e))
        os.rmdir(inner); print("FLATTEN  "+inner)
tmp=None
if os.path.isfile(src) and src.lower().endswith(".zip"):
    tmp=tempfile.mkdtemp(prefix="subs-")
    with zipfile.ZipFile(src) as z: z.extractall(tmp)
    src=tmp
subs={}
for f in find(src,SUB_EXT):
    c=codeof(os.path.basename(f))
    if c: subs.setdefault(c,[]).append(f)
seasons={s for s,_ in subs}   # only act on seasons the subtitles actually cover
m=mi=0
for v in sorted(find(show,VIDEO_EXT)):
    c=codeof(os.path.basename(v))
    if not c or c[0] not in seasons: continue
    ss=subs.get(c)
    if not ss: print("NO SUB   S%02dE%02d  %s"%(c[0],c[1],os.path.basename(v))); mi+=1; continue
    for s in ss:
        ext=os.path.splitext(s)[1].lower(); dst=os.path.splitext(v)[0]+"."+lang+ext
        print("S%02dE%02d  %s  ->  %s"%(c[0],c[1],os.path.basename(s),os.path.basename(dst)))
        if apply:
            shutil.copy2(s,dst)
            if archive:
                ad=os.path.join(show,"Subtitles","Season %02d"%c[0]); os.makedirs(ad,exist_ok=True)
                shutil.copy2(s,os.path.join(ad,os.path.basename(dst)))
        m+=1
print("\n%s  matched=%d  missing=%d"%("APPLIED" if apply else "DRY-RUN",m,mi))
if seasons: print("Applies to: " + ", ".join("Season %02d"%s for s in sorted(seasons)))
if tmp: shutil.rmtree(tmp,ignore_errors=True)
PYEOF
)

echo "== Jellyfin subtitle importer =="
mapfile -t SHOWLIST < <(find "$SHOWS" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
echo "Shows under $SHOWS:"
for i in "${!SHOWLIST[@]}"; do echo "$((i+1))- ${SHOWLIST[$i]}"; done
read -rp "Show (number or name): " SHOW_IN
if [[ "$SHOW_IN" =~ ^[0-9]+$ ]] && [ "$SHOW_IN" -ge 1 ] && [ "$SHOW_IN" -le "${#SHOWLIST[@]}" ]; then
  SHOW_IN="${SHOWLIST[$((SHOW_IN-1))]}"
fi
SHOW="$SHOW_IN"
[ -d "$SHOW" ] || SHOW="$SHOWS/$SHOW_IN"
[ -d "$SHOW" ] || { echo "Show folder not found: $SHOW"; exit 1; }
echo "Seasons in $(basename "$SHOW"):"
find "$SHOW" -maxdepth 1 -type d -iname 'Season *' -printf '  - %f\n' 2>/dev/null | sort
read -rp "Subtitles .zip or folder [/tmp/subs.zip]: " SRC
SRC="${SRC:-/tmp/subs.zip}"
[ -e "$SRC" ] || { echo "Subtitles not found: $SRC"; exit 1; }
read -rp "Language tag [ara]: " LANG
LANG="${LANG:-ara}"

echo "----- preview -----"
python3 -c "$PY" "$SHOW" "$SRC" "$LANG"
read -rp "Apply (place + archive + flatten)? [y/N] " A
if [[ "$A" =~ ^[Yy] ]]; then
  python3 -c "$PY" "$SHOW" "$SRC" "$LANG" apply archive flatten
  read -rsp "Jellyfin API key for auto-scan (blank to skip): " KEY; echo
  if [ -n "$KEY" ]; then
    curl -s -o /dev/null -w "scan: HTTP %{http_code}\n" -X POST \
      -H "Authorization: MediaBrowser Token=\"$KEY\"" \
      "$JELLYFIN_URL/Library/Refresh"
  fi
else
  echo "Aborted."
fi
