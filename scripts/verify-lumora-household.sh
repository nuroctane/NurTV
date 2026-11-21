#!/usr/bin/env bash
# scripts/verify-lumora-household.sh: hard gate for the household Lumora build.
#
#   verify-lumora-household.sh apk <file.apk>      refuse an APK that does not carry the setup
#   verify-lumora-household.sh tv  <ip[:port]>     fail unless the TV shows the full setup
#
# The required set lives in provision/lumora/household-required.json: providers (by name),
# favourites (count plus the UFC streams), enabled plugins, and the seed-done flag.
# Exit 0 only when every item is present. Anything missing prints and exits 1.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # keep /sdcard paths intact under Git Bash
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/_adb.sh"
REQ="$ROOT/provision/lumora/household-required.json"
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

mode=${1:-}; target=${2:-}
[ -n "$mode" ] && [ -n "$target" ] || { echo "usage: $0 apk <file> | tv <ip[:port]>" >&2; exit 2; }

case $mode in
  apk)
    [ -f "$target" ] || { echo "FAIL: $target does not exist" >&2; exit 1; }
    python -I - "$(win "$REQ")" "$(win "$target")" <<'PY'
import json, sys, zipfile
req = json.load(open(sys.argv[1], encoding='utf-8'))
z = zipfile.ZipFile(sys.argv[2])
names = set(z.namelist())
bad = [a for a in req['apk_assets'] if a not in names]
if not bad:
    seed = json.loads(z.read('assets/household-seed.json').decode('utf-8'))
    have = {p.get('name') for p in seed.get('iptvProviders', [])}
    bad += [f"seed provider {n}" for n in req['providers'] if n not in have and n not in (req.get('first_provider'), 'Rebel Live (PC)')]
    favs = set(seed.get('favoriteChannels', []))
    if len(favs) < req['min_favorites']:
        bad.append(f"seed favourites {len(favs)} < {req['min_favorites']}")
    bad += [f"seed favourite {f}" for f in req['favorites'] if f not in favs]
for b in bad: print(f"FAIL: APK missing {b}", file=sys.stderr)
if bad: sys.exit(1)
print("ok: APK carries the full household setup")
PY
    ;;
  tv)
    require_adb
    case $target in *:*) S=$target ;; *) S=$target:5555 ;; esac
    "$ADB_BIN" connect "$S" >/dev/null 2>&1 || true
    pkg=$(python -I -c "import json,sys;print(json.load(open(sys.argv[1],encoding='utf-8'))['package'])" "$(win "$REQ")")
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    "$ADB_BIN" -s "$S" shell "pm list packages $pkg" | tr -d '\r' | grep -qx "package:$pkg" \
      || { echo "FAIL: $pkg is not installed on $S" >&2; exit 1; }
    # Front end is golden state: the household tile must wear the same art the stock
    # Lumora tile had (apps/art/com.lumora.png), byte for byte, and keep its "Sports" name.
    art=/sdcard/Android/data/tv.cleantv.home/files/art/$pkg.png
    "$ADB_BIN" -s "$S" pull "$art" "$(win "$tmp/art.png")" >/dev/null 2>&1 || true
    if ! cmp -s "$tmp/art.png" "$ROOT/apps/art/com.lumora.png" || ! cmp -s "$ROOT/apps/art/$pkg.png" "$ROOT/apps/art/com.lumora.png"; then
      echo "FAIL: launcher art for $pkg differs from the golden Sports art" >&2; exit 1
    fi
    grep -qx "name.$pkg=Sports" "$ROOT/apps/home.conf" || { echo "FAIL: home.conf must name $pkg 'Sports'" >&2; exit 1; }
    "$ADB_BIN" -s "$S" exec-out run-as "$pkg" cat shared_prefs/iptv_prefs.xml > "$tmp/iptv.xml" 2>/dev/null || true
    "$ADB_BIN" -s "$S" exec-out run-as "$pkg" cat shared_prefs/plugin_prefs.xml > "$tmp/plugin.xml" 2>/dev/null || true
    python -I - "$(win "$REQ")" "$(win "$tmp/iptv.xml")" "$(win "$tmp/plugin.xml")" <<'PY'
import json, sys, xml.etree.ElementTree as ET
req = json.load(open(sys.argv[1], encoding='utf-8'))
def root(p):
    try: return ET.parse(p).getroot()
    except Exception: return None
iptv, plug = root(sys.argv[2]), root(sys.argv[3])
bad = []
if iptv is None:
    bad.append("iptv_prefs.xml unreadable (app never launched, or not the debuggable household build)")
else:
    for f in req.get('flags', [req['seed_flag']]):
        flag = iptv.find(f"boolean[@name='{f}']")
        if flag is None or flag.get('value') != 'true':
            bad.append(f"seed flag {f} not set (seed did not fully apply)")
    pj = iptv.find("string[@name='iptv_providers_json']")
    plist = json.loads(pj.text) if pj is not None and pj.text else []
    names = {p.get('name') for p in plist}
    first = req.get('first_provider')
    if first and (not plist or plist[0].get('name') != first):
        bad.append(f"{first} is not the first provider")
    bad += [f"provider {n}" for n in req['providers'] if n not in names]
    fs = iptv.find("set[@name='favorite_channel_ids']")
    favs = {e.text for e in fs.findall('string')} if fs is not None else set()
    if len(favs) < req['min_favorites']:
        bad.append(f"favourites {len(favs)} < {req['min_favorites']}")
    bad += [f"favourite {f}" for f in req['favorites'] if f not in favs]
ps = plug.find("set[@name='plugin_enabled_scripts']") if plug is not None else None
enabled = {e.text for e in ps.findall('string')} if ps is not None else set()
bad += [f"enabled plugin {p}" for p in req['plugins'] if p not in enabled]
for b in bad: print(f"FAIL: TV missing {b}", file=sys.stderr)
if bad: sys.exit(1)
print(f"ok: TV has {len(names)} providers, {len(favs)} favourites, {len(enabled)} plugins enabled")
PY
    ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
