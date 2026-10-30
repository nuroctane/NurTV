#!/usr/bin/env bash
# Guarded apply. Refuses to proceed if Amazon's launcher is not currently
# enabled, then runs the full pass. Non-interactive (-y = safe defaults).
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_adb.sh"
require_adb || exit 1
IP="${1:?usage: $0 <tv-ip>}"
S="$IP:5555"
export ADB_SERIAL="$S" ADB="$ADB_BIN"
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"

echo "== connection =="
"$ADB_BIN" connect "$S" >/dev/null 2>&1
"$ADB_BIN" -s "$S" wait-for-device || { echo "TV not reachable"; exit 1; }

echo "== guard: is com.amazon.tv.launcher enabled? =="
if "$ADB_BIN" -s "$S" shell pm list packages -e | tr -d '\r' \
   | awk '$0=="package:com.amazon.tv.launcher"{f=1} END{exit !f}'; then
  echo "   yes — safe to proceed"
else
  echo "   NO — Amazon's launcher is already disabled."
  echo "   ABORT: run ./scripts/emergency-restore.sh $IP first, then retry."
  exit 1
fi

echo "== guard: disk + ram =="
"$ADB_BIN" -s "$S" shell df /data 2>/dev/null | tr -d '\r' | tail -1
echo
echo "== launching full pass (defaults: prime=keep, alexa=keep, launcher=swap,"
echo "   dnsfilter=on, remove=none, smarttube=no) =="
echo "   the TV will reboot twice and the screen may go blank briefly — expected."
echo
exec "$DIR/go.sh" "$IP"
