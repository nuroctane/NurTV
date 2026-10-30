#!/usr/bin/env bash
# Blank screen / no home screen after a launcher swap.
# Detaches CleanTV's HOME hook and re-enables Amazon HOME. Leaves OTA unchanged.
# Usage: ./scripts/emergency-restore.sh <tv-ip>
set -euo pipefail
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"
source "$(dirname "${BASH_SOURCE[0]}")/_adb.sh"
require_adb || exit 1

IP="${1:-}"
[ -z "$IP" ] && { echo "usage: $0 <tv-ip>"; exit 1; }
S="$IP:5555"
"$ADB_BIN" -s "$S" get-state >/dev/null 2>&1 || { echo "no adb connection to $S"; exit 1; }

echo "re-enabling Amazon launcher"
"$ADB_BIN" -s "$S" shell cmd package install-existing com.amazon.tv.launcher 2>&1 | tr -d '\r'
"$ADB_BIN" -s "$S" shell pm enable com.amazon.tv.launcher 2>&1 | tr -d '\r'
echo "detaching the CleanTV HOME hook"
ADB="$ADB_BIN" ADB_SERIAL="$S" "$(dirname "${BASH_SOURCE[0]}")/../cleantv/launcher/install.sh" --undo
"$ADB_BIN" -s "$S" shell am start -a android.intent.action.MAIN \
  -c android.intent.category.HOME -p com.amazon.tv.launcher 2>&1 | tr -d '\r'

echo "rebooting"
"$ADB_BIN" -s "$S" reboot
echo
echo "if HOME is still unavailable, stop and inspect the launcher and accessibility state."
