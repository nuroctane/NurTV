#!/usr/bin/env bash
# Install the Watchbox extension APKs listed in provision/sources.json.
#
#   ./scripts/apply-sources.sh <tv-ip> [--dry-run] [--verify-only] [--with-intents]
#
# The extension packages are not part of golden-state.json until a later capture
# sees them on a TV. This script is what puts them on a new TV either way.
# It never uninstalls. It does not press HOME and it does not open apps unless
# --with-intents is passed (that one fires the Watchbox repo link).
#
# In-app CloudStream plugins, Zangetsu providers, and Arvio/Lumera add-ons are not
# applied here. See the "manual" list in provision/sources.json.
#
# Extension versions are not pinned: an extension that updated itself is fine.
# A package is verified by presence only; apk/sha256 are the install source
# used when it is missing, hash-checked before install.
set -uo pipefail

unset MSYS_NO_PATHCONV
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"
source "$(dirname "${BASH_SOURCE[0]}")/_adb.sh"
require_adb || exit 1

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE=$ROOT/provision/sources.json
IP=""; DRY=0; VERIFY_ONLY=0; WITH_INTENTS=0
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    --verify-only) VERIFY_ONLY=1 ;;
    --with-intents) WITH_INTENTS=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) IP=$a ;;
  esac
done
[ -n "$IP" ] || { echo "usage: $0 <tv-ip> [--dry-run] [--verify-only] [--with-intents]" >&2; exit 2; }
[ -f "$STATE" ] || { echo "no $STATE" >&2; exit 1; }
S="$IP:5555"

note() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
FAILED=0
fail() { warn "$*"; FAILED=1; }
sh_() { "$ADB_BIN" -s "$S" shell "$*" </dev/null 2>/dev/null | tr -d '\r'; }
sha() { sha256sum "$1" | awk '{print $1}'; }
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
vcode() { sh_ "dumpsys package $1" | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/firetv-sources.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

python - "$(win "$STATE")" "$(win "$WORK/ext.tsv")" <<'PY'
import json, sys
src = json.load(open(sys.argv[1], encoding='utf-8'))
with open(sys.argv[2], 'w', encoding='utf-8', newline='\n') as f:
    for e in src.get('extensions', []):
        f.write('\t'.join([e['package'], e['apk'], e['sha256']]) + '\n')
PY

echo "== media sources =="
"$ADB_BIN" connect "$S" >/dev/null 2>&1
if [ "$("$ADB_BIN" -s "$S" get-state 2>/dev/null)" != device ]; then
  echo "no adb to $S — run ./scripts/connect.sh $IP" >&2
  exit 1
fi

while IFS=$'\t' read -r pkg apk sum; do
  [ -n "$pkg" ] || continue
  if [ ! -f "$ROOT/$apk" ]; then
    fail "$pkg: $apk is missing from the repo"
    continue
  fi
  if [ "$(sha "$ROOT/$apk")" != "$sum" ]; then
    fail "$pkg: $apk does not match its recorded sha256"
    continue
  fi
  got=$(vcode "$pkg")
  if [ -n "$got" ]; then
    note "present   $pkg  code=$got (version not pinned)"
    continue
  fi
  if [ "$VERIFY_ONLY" = 1 ]; then
    fail "$pkg: not installed"
    continue
  fi
  if [ "$DRY" = 1 ]; then
    note "install   $pkg  from $apk (not installed)"
    continue
  fi
  out=$("$ADB_BIN" -s "$S" install -r "$ROOT/$apk" 2>&1 | grep -m1 -E 'Success|Failure|failed' || true)
  case $out in
    *Success*) ;;
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
      fail "$pkg: signed with a different key than the one installed — uninstall it on the TV by hand, then re-run (never done automatically)"
      continue ;;
    *) fail "$pkg: install failed: ${out:-no output}"; continue ;;
  esac
  new=$(vcode "$pkg")
  if [ -z "$new" ]; then
    fail "$pkg: install reported success but the package is not on the TV"
    continue
  fi
  remote=$(sh_ "pm path $pkg" | sed 's/^package://' | head -1)
  "$ADB_BIN" -s "$S" pull "$remote" "$WORK/check.apk" >/dev/null 2>&1
  if [ "$(sha "$WORK/check.apk")" = "$sum" ]; then
    note "installed $pkg  code=$new  sha256 verified"
  else
    fail "$pkg: installed APK does not match the recorded sha256"
  fi
done < "$WORK/ext.tsv"

if [ "$WITH_INTENTS" = 1 ] && [ "$DRY" = 0 ] && [ "$VERIFY_ONLY" = 0 ]; then
  # URL is inside the remote command so Git Bash does not rewrite https://.
  note "intent    aniyomi://add-repo (yuzono anime repo)"
  "$ADB_BIN" -s "$S" shell am start -a android.intent.action.VIEW \
    -d 'aniyomi://add-repo?url=https%3A%2F%2Fraw.githubusercontent.com%2Fyuzono%2Fanime-repo%2Frepo%2Findex.min.json' \
    >/dev/null 2>&1 || fail "Watchbox repo intent was not delivered"
fi

if [ "$FAILED" = 0 ]; then
  if [ "$DRY" = 1 ]; then note "extension package plan complete (no installs performed)"
  else note "extension packages match provision/sources.json"; fi
else
  echo "media sources failed — see the ! lines above" >&2
fi
exit "$FAILED"
