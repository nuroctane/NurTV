#!/usr/bin/env bash
# Snapshot everything needed to undo a debloat pass by hand.
# Usage: ./scripts/backup-packages.sh <tv-ip>
set -uo pipefail
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"
source "$(dirname "${BASH_SOURCE[0]}")/_adb.sh"
require_adb || exit 1

IP="${1:-}"
[ -z "$IP" ] && { echo "usage: $0 <tv-ip>"; exit 1; }
S="$IP:5555"

if ! "$ADB_BIN" -s "$S" get-state >/dev/null 2>&1; then
  echo "no adb connection to $S — run ./scripts/connect.sh $IP first"
  exit 1
fi

STAMP=$(date +%Y-%m-%d_%H%M%S)
OUT="$(cd "$(dirname "$0")/.." && pwd)/backups/$STAMP"
mkdir -p "$OUT"
echo "saving to $OUT"

dump() {
  local name=$1; shift
  "$@" | tr -d '\r' > "$OUT/$name.txt"
  echo "  $name.txt ($(wc -l < "$OUT/$name.txt" | tr -d ' ') lines)"
}

dump packages-enabled     "$ADB_BIN" -s "$S" shell pm list packages -e
dump packages-disabled    "$ADB_BIN" -s "$S" shell pm list packages -d
dump packages-all         "$ADB_BIN" -s "$S" shell pm list packages
dump packages-thirdparty  "$ADB_BIN" -s "$S" shell pm list packages -3

{
  for p in ro.product.model ro.product.device ro.build.display.id \
           ro.build.version.name ro.build.version.sdk ro.boot.verifiedbootstate; do
    printf '%s=%s\n' "$p" "$("$ADB_BIN" -s "$S" shell getprop "$p" | tr -d '\r')"
  done
} > "$OUT/props.txt"
echo "  props.txt"

"$ADB_BIN" -s "$S" shell settings list global | tr -d '\r' > "$OUT/settings-global.txt"
"$ADB_BIN" -s "$S" shell settings list secure | tr -d '\r' > "$OUT/settings-secure.txt"
echo "  settings-global.txt, settings-secure.txt"

echo
echo "DONE — this is your undo sheet. Do not delete backups/."
