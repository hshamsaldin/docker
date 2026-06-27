#!/usr/bin/env python3
"""
import-subs.py - attach subtitle files to episode videos for Jellyfin.

For every video under SHOW_DIR, find a subtitle (in SUBS_SOURCE, a folder or a
.zip) with the same SxxExx code and place a copy beside the video named
  <video-basename>.<lang>.<ext>   (e.g. ...S06E01....ara.srt / .ara.ass)
so Jellyfin auto-detects it. Dry-run by default; pass --apply to write.

Examples:
  python3 import-subs.py "/data/jellyfin/Shows/Game of Thrones" /tmp/subs.zip
  python3 import-subs.py "$SHOW" /tmp/subs.zip --apply --archive --flatten
  python3 import-subs.py "$SHOW" subs/ --apply \
      --jellyfin-url http://localhost:8096 --jellyfin-key YOUR_API_KEY
"""
import argparse, os, re, shutil, sys, tempfile, zipfile, urllib.request

VIDEO_EXT = (".mkv", ".mp4", ".avi", ".m4v")
SUB_EXT   = (".srt", ".ass", ".ssa", ".vtt", ".sub")
CODE_RE   = re.compile(r'[Ss](\d{1,2})[ ._-]*[Ee](\d{1,2})')

def code(name):
    m = CODE_RE.search(name)
    return (int(m.group(1)), int(m.group(2))) if m else None

def find(root, exts):
    out = []
    for d, _, files in os.walk(root):
        for f in files:
            if f.lower().endswith(exts):
                out.append(os.path.join(d, f))
    return out

def flatten_doubles(root, apply):
    doubles = [d for d, _, _ in os.walk(root)
               if os.path.basename(d) == os.path.basename(os.path.dirname(d))]
    for inner in sorted(doubles, key=len, reverse=True):
        parent = os.path.dirname(inner)
        print("FLATTEN  %s  ->  %s" % (inner, parent))
        if apply:
            for e in os.listdir(inner):
                shutil.move(os.path.join(inner, e), os.path.join(parent, e))
            os.rmdir(inner)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("show_dir")
    ap.add_argument("subs_source", help="a folder of subs OR a .zip file")
    ap.add_argument("--lang", default="ara", help="language tag (default: ara)")
    ap.add_argument("--apply", action="store_true", help="write files (default: dry-run)")
    ap.add_argument("--archive", action="store_true",
                    help="also copy matched subs into SHOW_DIR/Subtitles/Season NN/")
    ap.add_argument("--flatten", action="store_true",
                    help="flatten accidental X/X doubled folders first")
    ap.add_argument("--jellyfin-url", help="e.g. http://localhost:8096")
    ap.add_argument("--jellyfin-key", help="Jellyfin API key (to trigger a scan)")
    a = ap.parse_args()

    if not os.path.isdir(a.show_dir):
        sys.exit("show_dir not found: " + a.show_dir)
    if a.flatten:
        flatten_doubles(a.show_dir, a.apply)

    tmp, src_dir = None, a.subs_source
    if os.path.isfile(a.subs_source) and a.subs_source.lower().endswith(".zip"):
        tmp = tempfile.mkdtemp(prefix="subs-")
        with zipfile.ZipFile(a.subs_source) as z:
            z.extractall(tmp)
        src_dir = tmp
    elif not os.path.isdir(a.subs_source):
        sys.exit("subs_source not found: " + a.subs_source)

    subs = {}
    for f in find(src_dir, SUB_EXT):
        c = code(os.path.basename(f))
        if c:
            subs.setdefault(c, []).append(f)

    matched = missing = 0
    for v in sorted(find(a.show_dir, VIDEO_EXT)):
        c = code(os.path.basename(v))
        if not c:
            continue
        srcs = subs.get(c)
        if not srcs:
            print("NO SUB   S%02dE%02d  %s" % (c[0], c[1], os.path.basename(v))); missing += 1; continue
        for src in srcs:
            ext = os.path.splitext(src)[1].lower()
            dst = os.path.splitext(v)[0] + "." + a.lang + ext
            print("S%02dE%02d  %s  ->  %s" % (c[0], c[1], os.path.basename(src), os.path.basename(dst)))
            if a.apply:
                shutil.copy2(src, dst)
                if a.archive:
                    adir = os.path.join(a.show_dir, "Subtitles", "Season %02d" % c[0])
                    os.makedirs(adir, exist_ok=True)
                    shutil.copy2(src, os.path.join(adir, os.path.basename(dst)))
            matched += 1

    print("\n%s  matched=%d  missing=%d" %
          ("APPLIED" if a.apply else "(dry-run -- add --apply)", matched, missing))
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)

    if a.apply and a.jellyfin_url and a.jellyfin_key:
        url = a.jellyfin_url.rstrip("/") + "/Library/Refresh?api_key=" + a.jellyfin_key
        try:
            urllib.request.urlopen(urllib.request.Request(url, method="POST"), timeout=10)
            print("Triggered Jellyfin library scan.")
        except Exception as e:
            print("Jellyfin scan failed:", e)

if __name__ == "__main__":
    main()
