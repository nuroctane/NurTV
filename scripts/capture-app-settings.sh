#!/usr/bin/env bash
# Capture app state that lives in private data, filtering likely sign-in data.
#
#   ./scripts/capture-app-settings.sh <working-tv-ip>
#
# SmartTube (SponsorBlock, hide shorts, player preset), S0undTV (the three
# Luminous proxy slots), CloudStream (repos + downloaded plugins), Zangetsu
# (provider repos + installed providers) and Watchbox (repo list) all allow
# Android backup, so this runs `adb backup -noapk` for them. The TV shows a
# "Back up my data" screen: press the button there, leave the password empty.
# Arvio, Lumera and Atlantic forbid backup; see provision/sources.json.
#
# The raw backup holds sign-in sessions, so it is never kept: app_settings.py
# writes private/app-settings/app-settings.ab without caches, webview data or
# credential-looking files and keys. Filtering is heuristic; treat it as sensitive.
# Provisioning can restore it only with --restore-app-settings.
#
# The apps are force-stopped by the backup, so pick a time nothing is playing.
set -uo pipefail
unset MSYS_NO_PATHCONV
source "$(dirname "${BASH_SOURCE[0]}")/_adb.sh"
require_adb || exit 1

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IP=${1:-}
[ -n "$IP" ] || { echo "usage: $0 <working-tv-ip>" >&2; exit 2; }
S="$IP:5555"
PKGS=(org.smarttube.stable com.s0und.s0undtv com.lagradost.cloudstream3 com.spyou.watch_app space.nicart.watchbox.tv)
OUT=$ROOT/private/app-settings
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

"$ADB_BIN" connect "$S" >/dev/null 2>&1
"$ADB_BIN" -s "$S" get-state >/dev/null 2>&1 || { echo "TV $S is not reachable over adb" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/firetv-appsettings.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

echo "== backup ${PKGS[*]} =="
echo "   On the TV: press 'Back up my data' (no password). Waiting up to 2 minutes."
timeout 150 "$ADB_BIN" -s "$S" backup -noapk -f "$(win "$WORK/raw.ab")" "${PKGS[@]}" </dev/null
size=$(stat -c %s "$WORK/raw.ab" 2>/dev/null || echo 0)
[ "$size" -gt 100 ] || { echo "   ! backup is empty: the TV prompt was not accepted, or it timed out" >&2; exit 1; }

echo "== sanitize =="
mkdir -p "$OUT"
python -I "$(win "$ROOT/scripts/app_settings.py")" sanitize "$(win "$WORK/raw.ab")" "$(win "$OUT/app-settings.new.ab")" || exit 1
mv -f "$OUT/app-settings.new.ab" "$OUT/app-settings.ab"
sha256sum "$OUT/app-settings.ab" | awk '{print $1}' > "$OUT/app-settings.ab.sha256"
echo "   wrote private/app-settings/app-settings.ab ($(stat -c %s "$OUT/app-settings.ab") bytes)"
echo "   check the drop list above: anything that is a preference rather than a sign-in"
echo "   means SECRET in scripts/app_settings.py matched too much."
