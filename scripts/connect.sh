#!/usr/bin/env bash
# Connect to the TV over ADB.
# Works in MSYS2/UCRT64, Git Bash, WSL, macOS and Linux.
# Usage: ./scripts/connect.sh <tv-ip>
set -uo pipefail

# Git Bash / MSYS2 rewrite Unix-looking arguments into Windows paths, which
# would turn /sdcard/... into C:/Program Files/Git/sdcard/... .
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"

source "$(dirname "${BASH_SOURCE[0]}")/_adb.sh"
ADB_VERBOSE=1 require_adb || exit 1

# The TV's address is local state and must never be committed. Set TV_IP, write
# it to .tv-ip (gitignored), or pass it as the first argument.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IP="${1:-${TV_IP:-}}"
if [ -z "$IP" ] && [ -f "$ROOT/.tv-ip" ]; then
  IP="$(tr -d '[:space:]' < "$ROOT/.tv-ip")"
fi
if [ -z "$IP" ]; then
  echo "usage: $0 <tv-ip>      (or set TV_IP, or write the address to .tv-ip)"
  exit 1
fi
S="$IP:5555"

echo "== adb =="
"$ADB_BIN" version | head -2
"$ADB_BIN" kill-server >/dev/null 2>&1
"$ADB_BIN" start-server >/dev/null 2>&1

echo
echo "connecting to $S — accept the prompt ON THE TV"
"$ADB_BIN" connect "$S" || true
"$ADB_BIN" -s "$S" wait-for-device || {
  echo
  echo "did not come up. check:"
  echo "  - ADB debugging is ON (Settings → My Fire TV → About → OK x7 → Developer Options)"
  echo "  - the TV and this machine are on the same subnet"
  echo "  - you accepted the 'Allow ADB debugging?' prompt on the TV"
  exit 1
}

echo
echo "model   : $("$ADB_BIN" -s "$S" shell getprop ro.product.model | tr -d '\r')"
echo "device  : $("$ADB_BIN" -s "$S" shell getprop ro.product.device | tr -d '\r')"
echo "fire os : $("$ADB_BIN" -s "$S" shell getprop ro.build.version.name | tr -d '\r')"
echo "sdk     : $("$ADB_BIN" -s "$S" shell getprop ro.build.version.sdk | tr -d '\r')"
echo
echo "# paste these into this shell:"
echo "export ADB_SERIAL=$S"
echo "export ADB=$ADB_BIN"
