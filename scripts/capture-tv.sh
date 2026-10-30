#!/usr/bin/env bash
# Capture this TV's whole setup into the repo, so scripts/provision-tv.sh can put
# the same thing onto another TV of the same model.
#
#   ./scripts/capture-tv.sh <tv-ip> [--force]
#
# READ-ONLY on the device: nothing is installed, enabled, disabled, started or
# removed. Re-run it after any change on the TV; it only rewrites what differs.
#
# It writes under provision/ (see provision/README.md):
#   provision/golden-state.json   device guard + every package with its APK hash
#   provision/apk/<pkg>.apk       byte-exact copies of APKs the repo lacks
# and refreshes the pieces this repo already owns:
#   apps/home.conf, apps/art/*.png, apps/wallpapers/<applied>.jpg
# and stages the launcher APK where CleanTV's own installer expects it
# (cleantv/launcher/build/ + version.env), so the HOME takeover stays checksum-verified.
set -uo pipefail

# Git Bash rewrites Unix-looking arguments into Windows paths, which would turn
# /sdcard/... into C:/Program Files/Git/sdcard/... — so exclude the device prefixes.
# MSYS_NO_PATHCONV must NOT be set here: it also stops the conversion of this
# script's own temp paths, and then native adb.exe writes its pulls somewhere bash
# cannot read (a pull that reports success into a path that does not exist).
# Excluding the device prefixes is the precise fix; anything else converts normally.
unset MSYS_NO_PATHCONV
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"
source "$(dirname "${BASH_SOURCE[0]}")/_adb.sh"
require_adb || exit 1

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IP=""; FORCE=0
for a in "$@"; do
  case $a in
    --force) FORCE=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) IP=$a ;;
  esac
done
[ -n "$IP" ] || { echo "usage: $0 <tv-ip> [--force]" >&2; exit 2; }
S="$IP:5555"

# Part of the TV, not part of what was done to it: system overlays, and Netflix-
# style apps whose updates the Appstore restores on any Fire TV of this model.
# *.household are side-by-side prototypes (provision/CUSTOM-CLIENTS.md), untested.
EXCLUDE='^(com\.amazon\..*overlay.*|com\.netflix\.ninja|com\.android\..*|com\.google\..*|android|.*\.household)$'

STAMP=$(date +%Y-%m-%d_%H%M%S)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/firetv-capture.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/apk" "$WORK/art"

sh_() { "$ADB_BIN" -s "$S" shell "$*" </dev/null 2>/dev/null | tr -d '\r'; }
prop() { sh_ "getprop $1"; }
sha() { sha256sum "$1" | awk '{print $1}'; }
rel() { printf '%s' "${1#"$ROOT"/}"; }
# Native python needs Windows paths, and Git Bash only converts them itself when the
# caller has not exported MSYS_NO_PATHCONV (device paths need that variable). Convert
# explicitly, so the script behaves the same either way.
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

"$ADB_BIN" connect "$S" >/dev/null 2>&1
[ "$("$ADB_BIN" -s "$S" get-state 2>/dev/null)" = device ] || { echo "no adb to $S — run ./scripts/connect.sh $IP" >&2; exit 1; }

MODEL=$(prop ro.product.model); DEVICE=$(prop ro.product.device)
SDK=$(prop ro.build.version.sdk); FIREOS=$(prop ro.build.version.name)
BUILD=$(prop ro.build.display.id); ABI=$(prop ro.product.cpu.abi)

echo "== device =="
echo "  $DEVICE / $MODEL  Fire OS $FIREOS (sdk $SDK, $ABI)"

# Refuse to overwrite a golden state that came from another model, so two TVs
# cannot silently merge into one profile.
if [ -f "$ROOT/provision/golden-state.json" ] && [ "$FORCE" = 0 ]; then
  prev=$(python - "$(win "$ROOT/provision/golden-state.json")" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))["device"]
print(f'{g["device"]}|{g["model"]}|{g["sdk"]}')
PY
)
  if [ "$prev" != "$DEVICE|$MODEL|$SDK" ]; then
    echo >&2
    echo "provision/golden-state.json came from a different TV:" >&2
    echo "  recorded: $prev" >&2
    echo "  this TV : $DEVICE|$MODEL|$SDK" >&2
    echo "pass --force to capture this TV anyway (the old state is overwritten)." >&2
    exit 1
  fi
fi

echo
echo "== hash index of the APKs already in the repo =="
: > "$WORK/index.tsv"
while IFS= read -r f; do
  printf '%s\t%s\n' "$(sha "$f")" "$(rel "$f")" >> "$WORK/index.tsv"
done < <(find "$ROOT/apps" "$ROOT/provision" "$ROOT/cleantv/launcher/build" -name '*.apk' -type f 2>/dev/null)
echo "  $(wc -l < "$WORK/index.tsv" | tr -d ' ') files indexed"

echo
echo "== packages (third-party) =="
: > "$WORK/apps.tsv"
PULL_FAILED=0
mapfile -t PKGS < <(sh_ "pm list packages -3" | sed 's/^package://' | sort -u)
for p in "${PKGS[@]}"; do
  [ -n "$p" ] || continue
  if printf '%s' "$p" | grep -Eq "$EXCLUDE"; then
    echo "  skip   $p (system-managed on this model)"
    continue
  fi
  dump=$("$ADB_BIN" -s "$S" shell "dumpsys package $p" 2>/dev/null | tr -d '\r')
  vname=$(printf '%s' "$dump" | sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -1)
  vcode=$(printf '%s' "$dump" | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1)
  mapfile -t paths < <(sh_ "pm path $p" | sed 's/^package://')
  [ "${#paths[@]}" -gt 0 ] || { echo "  skip   $p (no APK path)"; continue; }

  mode=install; files=(); hashes=()
  for i in "${!paths[@]}"; do
    local_apk=$WORK/apk/$p.$i.apk
    if "$ADB_BIN" -s "$S" pull "${paths[$i]}" "$local_apk" >/dev/null 2>&1; then
      files+=("$local_apk"); hashes+=("$(sha "$local_apk")")
    else
      echo "  FAIL   $p (could not pull ${paths[$i]})" >&2
      files+=(""); hashes+=("")
      PULL_FAILED=1
    fi
  done
  [ "${#paths[@]}" -gt 1 ] && mode=install-multiple

  # Keep the repo copy when one already matches byte-for-byte; only novel or
  # changed APKs are copied into provision/apk/. Build outputs are not a durable
  # home for a golden state (apps/webwrap/out/ is git-ignored), so those get a copy.
  apks=(); novel=0
  for i in "${!paths[@]}"; do
    h=${hashes[$i]}
    [ -n "$h" ] || continue
    hit=$(awk -F'\t' -v h="$h" '$1==h {print $2; exit}' "$WORK/index.tsv")
    case $hit in
      apps/webwrap/out/*)
        mkdir -p "$ROOT/provision/apk"
        cp "$ROOT/$hit" "$ROOT/provision/apk/$p.apk"
        apks+=("provision/apk/$p.apk"); novel=1
        printf '%s\t%s\n' "$h" "provision/apk/$p.apk" >> "$WORK/index.tsv"
        ;;
      ?*)
        apks+=("$hit") ;;
      *)
        ext=$(basename "${paths[$i]}")               # base.apk / split_config.armeabi_v7a.apk
        name=$p.apk; [ "${#paths[@]}" -gt 1 ] && name=$p.$ext
        mkdir -p "$ROOT/provision/apk"
        cp "${files[$i]}" "$ROOT/provision/apk/$name"
        apks+=("provision/apk/$name"); novel=1
        printf '%s\t%s\n' "$h" "provision/apk/$name" >> "$WORK/index.tsv"
        ;;
    esac
  done

  if [ "${#apks[@]}" -eq 0 ]; then
    echo "  FAIL   $p (nothing readable to record)" >&2
    PULL_FAILED=1
    continue
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$p" "${vname:-}" "${vcode:-}" "$mode" \
    "$(printf '%s,' "${apks[@]}" | sed 's/,$//')" >> "$WORK/apps.tsv"
  printf '  %-26s %-12s code=%-8s %s\n' "$p" "${vname:-?}" "${vcode:-?}" \
    "$([ "$novel" = 1 ] && echo 'copied into provision/apk/ (not in the repo yet)' || echo 'already in the repo')"
done

# A partial inventory is worse than none: it would describe the repo, not the TV.
if [ "$PULL_FAILED" = 1 ]; then
  echo >&2
  echo "capture aborted: at least one installed APK could not be pulled. Nothing was" >&2
  echo "written to provision/golden-state.json. Check adb's access to /data/app with:" >&2
  echo "  \"$ADB_BIN\" -s $S shell pm path <package>" >&2
  echo "(provision/apk/ copies made before the failure stay; re-run to finish.)" >&2
  exit 1
fi

echo
echo "== launcher config + assets =="
HD=/sdcard/Android/data/tv.cleantv.home/files

# home.conf: the device is the source of truth. Keep the old copy if it differs.
if [ "$(sh_ "test -f $HD/home.conf && echo yes")" = yes ] \
   && "$ADB_BIN" -s "$S" pull "$HD/home.conf" "$WORK/home.conf" >/dev/null 2>&1 \
   && [ -s "$WORK/home.conf" ]; then
  # Values are compared, never bytes: the launcher rewrites its own copy and drops
  # the comments that keep this file readable in the repo.
  if python "$(win "$ROOT/scripts/home_conf.py")" diff "$(win "$ROOT/apps/home.conf")" \
       "$(win "$WORK/home.conf")" > "$WORK/hc.diff" 2>/dev/null; then
    echo "  home.conf   unchanged"
  else
    mkdir -p "$ROOT/backups/pre-capture-$STAMP"
    [ -f "$ROOT/apps/home.conf" ] && cp "$ROOT/apps/home.conf" "$ROOT/backups/pre-capture-$STAMP/home.conf"
    sed 's/^/  change  /' "$WORK/hc.diff"
    python "$(win "$ROOT/scripts/home_conf.py")" merge "$(win "$ROOT/apps/home.conf")" \
      "$(win "$WORK/home.conf")" | sed 's/^/  /'
    echo "  home.conf   previous copy in backups/pre-capture-$STAMP/"
  fi
elif [ "$(sh_ "test -f $HD/home.conf && echo yes")" = yes ]; then
  echo "  home.conf   could not be pulled — left as is" >&2
else
  echo "  home.conf   not on the device — left as is"
fi

mkdir -p "$ROOT/apps/art"
for f in $(sh_ "ls $HD/art" 2>/dev/null); do
  case $f in *.png) ;; *) continue ;; esac
  "$ADB_BIN" -s "$S" pull "$HD/art/$f" "$WORK/art/$f" >/dev/null 2>&1 || continue
  if [ -f "$ROOT/apps/art/$f" ] && [ "$(sha "$ROOT/apps/art/$f")" = "$(sha "$WORK/art/$f")" ]; then
    echo "  art/$f   unchanged"
  else
    cp "$WORK/art/$f" "$ROOT/apps/art/$f"
    echo "  art/$f   refreshed from the TV"
  fi
done

WALLPAPER=""
if [ "$(sh_ "test -f $HD/wallpaper.jpg && echo yes")" = yes ] \
   && "$ADB_BIN" -s "$S" pull "$HD/wallpaper.jpg" "$WORK/wallpaper.jpg" >/dev/null 2>&1 \
   && [ -s "$WORK/wallpaper.jpg" ]; then
  wh=$(sha "$WORK/wallpaper.jpg")
  for f in "$ROOT"/apps/wallpapers/*.jpg; do
    [ -f "$f" ] || continue
    if [ "$(sha "$f")" = "$wh" ]; then WALLPAPER=$(rel "$f"); break; fi
  done
  if [ -z "$WALLPAPER" ]; then
    WALLPAPER="apps/wallpapers/device-$(printf '%s' "$wh" | cut -c1-8).jpg"
    cp "$WORK/wallpaper.jpg" "$ROOT/$WALLPAPER"
    echo "  wallpaper   $WALLPAPER (new: not in apps/wallpapers/ before)"
  else
    echo "  wallpaper   $WALLPAPER"
  fi
elif [ "$(sh_ "test -f $HD/wallpaper.jpg && echo yes")" = yes ]; then
  echo "  wallpaper   could not be pulled — left as is" >&2
fi

echo
echo "== launcher APK for CleanTV's installer =="
LAUNCHER_APK=$(awk -F'\t' '$1=="tv.cleantv.home" {print $5}' "$WORK/apps.tsv" | cut -d, -f1)
ENV=$ROOT/cleantv/launcher/version.env
if [ -n "$LAUNCHER_APK" ] && [ -f "$ROOT/$LAUNCHER_APK" ] && [ -f "$ENV" ]; then
  LVER=$(sed -n 's/^VERSION=//p' "$ENV" | head -1)
  LCODE=$(awk -F'\t' '$1=="tv.cleantv.home" {print $3}' "$WORK/apps.tsv")
  LHASH=$(sha "$ROOT/$LAUNCHER_APK")
  mkdir -p "$ROOT/cleantv/launcher/build"
  cp "$ROOT/$LAUNCHER_APK" "$ROOT/cleantv/launcher/build/cleantv-home-$LVER.apk"
  if [ "$(sed -n 's/^APK_SHA256=//p' "$ENV" | head -1)" != "$LHASH" ]; then
    sed -i.orig -e "s|^VERSION_CODE=.*|VERSION_CODE=$LCODE|" \
                  -e "s|^APK_SHA256=.*|APK_SHA256=$LHASH|" "$ENV" && rm -f "$ENV.orig"
    echo "  version.env updated: VERSION_CODE=$LCODE, APK_SHA256=${LHASH:0:16}…"
  else
    echo "  version.env already matches"
  fi
  echo "  staged cleantv/launcher/build/cleantv-home-$LVER.apk (from $LAUNCHER_APK)"
elif [ -z "$LAUNCHER_APK" ]; then
  echo "  tv.cleantv.home is not installed on this TV — skipped"
else
  echo "  version.env missing — skipped" >&2
fi

echo
echo "== golden-state.json =="
sh_ "pm list packages -d" | sed 's/^package://' | sort > "$WORK/disabled.txt"
{
  printf 'always_on_vpn_app=%s\n' "$(sh_ "settings get secure always_on_vpn_app")"
  printf 'alarm_manager_constants=%s\n' "$(sh_ "settings get global alarm_manager_constants")"
  printf 'enabled_accessibility_services=%s\n' "$(sh_ "settings get secure enabled_accessibility_services")"
} > "$WORK/settings.txt"
printf '%s\n' "$WALLPAPER" > "$WORK/wallpaper.path"

mkdir -p "$ROOT/provision"
python - "$(win "$ROOT")" "$(win "$WORK")" "$STAMP" "$DEVICE" "$MODEL" "$SDK" \
  "$FIREOS" "$BUILD" "$ABI" <<'PY'
import hashlib, json, os, sys
root, work, stamp, device, model, sdk, fireos, build, abi = sys.argv[1:10]

def rows(name):
    path = os.path.join(work, name)
    if not os.path.exists(path):
        return []
    return [l.rstrip('\n').split('\t') for l in open(path, encoding='utf-8') if l.strip()]

packages = []
for pkg, vname, vcode, mode, apks in rows('apps.tsv'):
    files = apks.split(',')
    packages.append({
        'package': pkg,
        'versionName': vname or None,
        'versionCode': int(vcode) if vcode.isdigit() else None,
        'install': mode,
        'apk': files,
        'sha256': [hashlib.sha256(open(os.path.join(root, a), 'rb').read()).hexdigest() for a in files],
        'role': ('launcher' if pkg == 'tv.cleantv.home'
                 else 'dnsfilter' if pkg == 'dnsfilter.android' else 'app'),
    })
packages.sort(key=lambda e: (e['role'] != 'launcher', e['role'] != 'dnsfilter', e['package']))

settings = {}
for line in open(os.path.join(work, 'settings.txt'), encoding='utf-8'):
    if '=' in line:
        k, v = line.rstrip('\n').split('=', 1)
        settings[k] = None if v in ('', 'null') else v

state = {
    '_comment': 'Captured by scripts/capture-tv.sh — this is what the TV actually has. '
                'Do not hand-edit; re-run capture after changing anything on the TV.',
    'captured_at': stamp,
    'device': {'device': device, 'model': model, 'sdk': int(sdk), 'fire_os': fireos,
               'build': build, 'abi': abi},
    'guard': {'ro.product.device': device, 'ro.product.model': model,
              'ro.build.version.sdk': str(sdk)},
    'config': {'home_conf': 'apps/home.conf', 'art': 'apps/art',
               'wallpaper': open(os.path.join(work, 'wallpaper.path'), encoding='utf-8').read().strip(),
               'cleantv_conf': 'cleantv/cleantv.conf'},
    'packages': packages,
    'disabled_packages': [l for l in open(os.path.join(work, 'disabled.txt'), encoding='utf-8')
                          .read().splitlines() if l],
    'settings': settings,
}
path = os.path.join(root, 'provision', 'golden-state.json')
with open(path, 'w', encoding='utf-8', newline='\n') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
print(f"  {len(packages)} packages, {len(state['disabled_packages'])} disabled -> provision/golden-state.json")
PY

echo
echo "DONE — capture complete. Import it with: ./scripts/provision-tv.sh <new-tv-ip>"
