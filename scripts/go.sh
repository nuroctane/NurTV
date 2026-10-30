#!/usr/bin/env bash
# One shot: connect → backup → preflight → apply → verify.
# Usage: ./scripts/go.sh <tv-ip> [--dry]
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_adb.sh"
require_adb || exit 1

IP="${1:-}"; [ -z "$IP" ] && { echo "usage: $0 <tv-ip> [--dry]"; exit 1; }
DRY="${2:-}"
export ADB_SERIAL="$IP:5555"
export ADB="$ADB_BIN"
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"

banner() { printf '\n== %s ==\n' "$*"; }

banner "1/5 connect"
"$DIR/connect.sh" "$IP" || exit 1

banner "2/5 backup"
"$DIR/backup-packages.sh" "$IP" || exit 1

banner "3/5 preflight (read-only)"
( cd "$DIR/../cleantv" && ./scripts/preflight.sh ) || exit 1

if [ "$DRY" = "--dry" ]; then banner "stopped at --dry (nothing changed)"; exit 0; fi

banner "4/5 apply"
( cd "$DIR/../cleantv" && ./scripts/all.sh -y ) || { echo "apply FAILED — run ./scripts/emergency-restore.sh $IP"; exit 1; }

banner "5/5 verify"
( cd "$DIR/../cleantv" && ./scripts/verify.sh )
