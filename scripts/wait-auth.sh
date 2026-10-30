#!/usr/bin/env bash
# Waits for the TV to authorize this machine, then immediately does the
# read-only work (identity, backup, preflight). Changes nothing on the TV.
# Usage: ./scripts/wait-auth.sh <tv-ip> [seconds]
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_adb.sh"
require_adb || exit 1
IP="${1:-}"; [ -z "$IP" ] && { echo "usage: $0 <tv-ip> [seconds]"; exit 1; }
LIMIT="${2:-300}"
S="$IP:5555"
export ADB_SERIAL="$S" ADB="$ADB_BIN"
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"

state_of() { "$ADB_BIN" devices 2>/dev/null | awk -v s="$S" '$1==s {print $2; found=1} END{if(!found) print "absent"}'; }

echo "watching $S for up to ${LIMIT}s"
i=0
while [ "$i" -lt "$LIMIT" ]; do
  st=$(state_of)
  if [ "$st" = "device" ]; then
    echo ">>> AUTHORIZED after ${i}s"
    echo
    echo "== identity =="
    for p in ro.product.model ro.product.device ro.build.version.name ro.build.version.sdk ro.build.display.id; do
      printf '%-24s %s\n' "$p" "$("$ADB_BIN" -s "$S" shell getprop "$p" | tr -d '\r')"
    done
    echo
    echo "== backup (read-only) =="
    "$DIR/backup-packages.sh" "$IP"
    echo
    echo "== preflight (read-only) =="
    ( cd "$DIR/../cleantv" && ./scripts/preflight.sh )
    exit 0
  fi
  if [ $((i % 15)) -eq 0 ]; then
    [ "$i" -gt 0 ] && echo "  ${i}s — state=$st, re-prompting"
    "$ADB_BIN" connect "$S" >/dev/null 2>&1
  fi
  sleep 5
  i=$((i+5))
done
echo ">>> TIMED OUT at ${LIMIT}s (last state: $(state_of))"
echo "    if no prompt appeared on the TV: Developer Options → Revoke ADB"
echo "    authorizations, then run this again."
exit 1
