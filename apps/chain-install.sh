#!/usr/bin/env bash
# Opens each Appstore product page as the previous app finishes installing.
# The user still has to tap "Get" — Amazon exposes no install API, and blind
# keyevent simulation could tap the wrong thing on a store page.
# Usage: ./apps/chain-install.sh [tv-ip]
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/../scripts/_adb.sh"
require_adb || exit 1
IP="${1:?usage: $0 <tv-ip>}"
S="$IP:5555"
"$ADB_BIN" connect "$S" >/dev/null 2>&1 || { echo "TV unreachable"; exit 1; }

SETTLE=${SETTLE:-60}     # let a download finish before stealing the screen
LIMIT=${LIMIT:-1200}     # 20 min overall

open_asin() {
  echo "  >>> opening $2 ($1) — tap Get on the TV"
  MSYS_NO_PATHCONV=1 "$ADB_BIN" -s "$S" shell am start \
    -a android.intent.action.VIEW -d "amzn://apps/android?asin=$1" >/dev/null 2>&1
}

pkgs() { "$ADB_BIN" -s "$S" shell pm list packages 2>/dev/null | tr -d '\r' \
         | sed 's/^package://' | awk '!/overlay|^tv\.cleantv\.home$|^dnsfilter\.android$/'; }

BASE=$(pkgs | sort)
echo "baseline third-party apps: $(printf '%s\n' "$BASE" | awk 'NF' | wc -l | tr -d ' ')"

wait_new() {   # $1 = label ; prints the new package name when one appears
  local i=0
  while [ "$i" -lt "$LIMIT" ]; do
    local cur new
    cur=$(pkgs | sort)
    new=$(comm -13 <(printf '%s\n' "$BASE") <(printf '%s\n' "$cur") | awk 'NF')
    if [ -n "$new" ]; then printf '%s\n' "$new"; return 0; fi
    [ $((i % 30)) -eq 0 ] && echo "  waiting for $1 (${i}s)"
    sleep 10; i=$((i+10))
  done
  return 1
}

echo "1/3 Twitch — page should already be open on the TV; waiting for the install"
if T=$(wait_new Twitch); then
  echo "  installed: $T"
  sleep "$SETTLE"
  open_asin B0DNRNVYDQ Kick
  if K=$(wait_new Kick); then
    echo "  installed: $K"
    sleep "$SETTLE"
    open_asin B08K9FXY9B Rumble
    if R=$(wait_new Rumble); then
      echo "  installed: $R"
      sleep 5
      { printf '%s\n' "$T" "$K" "$R" | tr ' ' '\n' | awk 'NF' | sort -u; } > "$DIR/installed.txt"
      open_asin_pkgs=$(awk 'NF' "$DIR/installed.txt" | paste -sd, -)
      echo
      echo "ALL THREE INSTALLED:"
      cat "$DIR/installed.txt"
      echo
      echo "apps.order candidate: org.smarttube.stable,com.amazon.venezia,$open_asin_pkgs"
      exit 0
    fi
  fi
fi
echo "chain stopped — nothing more opened. installed so far:"
[ -f "$DIR/installed.txt" ] && cat "$DIR/installed.txt" || echo "  (none detected)"
exit 1
