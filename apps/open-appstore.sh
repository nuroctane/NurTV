#!/usr/bin/env bash
# Open an Amazon Appstore product page on the TV.
# Usage: ./apps/open-appstore.sh <ASIN> [tv-ip]
# IP comes from the second argument, else $TV_IP, else the one adb device on :5555.
# There is no baked-in address — a stale default sends this at a TV that is off.
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/../scripts/_adb.sh"
require_adb || exit 1
ASIN="${1:?usage: $0 <ASIN> [tv-ip]   Twitch=B007SOQBCM Kick=B0DNRNVYDQ Rumble=B08K9FXY9B}"
if [ -n "${2:-}" ]; then
  IP=$2
elif [ -n "${TV_IP:-}" ]; then
  IP=$TV_IP
else
  mapfile -t _tvs < <("$ADB_BIN" devices | sed -n 's/^\([0-9.]*\):5555[[:space:]]*device$/\1/p')
  if [ "${#_tvs[@]}" -eq 1 ]; then
    IP=${_tvs[0]}
  else
    echo "no TV ip: pass it as the second argument or set TV_IP (adb has ${#_tvs[@]} device(s) on :5555)" >&2
    exit 1
  fi
fi
S="$IP:5555"
"$ADB_BIN" connect "$S" >/dev/null 2>&1
"$ADB_BIN" -s "$S" get-state >/dev/null 2>&1 || { echo "TV not connected"; exit 1; }

echo "Appstore package: $("$ADB_BIN" -s "$S" shell pm list packages -e com.amazon.venezia | tr -d '\r')"
echo "opening amzn://apps/android?asin=$ASIN on the TV"
MSYS_NO_PATHCONV=1 "$ADB_BIN" -s "$S" shell am start \
  -a android.intent.action.VIEW -d "amzn://apps/android?asin=$ASIN" 2>&1 | tr -d '\r'
echo
echo "on the TV: tap Get. tell Nur when it finishes and the next ASIN opens."
