#!/usr/bin/env bash
# Read-only checks. No reboots, force-stops, app launches, or full log collection.
set -euo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_adb.sh"
require_adb
[[ -n ${1:-} ]] || { echo "usage: $0 <tv-ip>" >&2; exit 2; }
export ADB="$ADB_BIN" ADB_SERIAL="$1:5555"
source "$DIR/../cleantv/scripts/lib.sh"
need_device
echo "WebView provider (reported identity, not a security certification):"
dev 'dumpsys webviewupdate' | sed -n '/Current WebView package/p'
echo "Always-on filter: $(dev1 settings get secure always_on_vpn_app)"
echo "VPN lockdown: $(dev1 settings get secure always_on_vpn_lockdown) (null/0 means no lockdown)"
echo "Privacy setting values (configured values do not prove enforcement):"
for key in amz_limit_ad_tracking USAGE_METRICS_UPLOAD_ENABLED settingsApp:appUsageData:value settingsApp:deviceUsageData:value; do
  echo "  $key=$(dev1 settings get secure "$key")"
done
echo "Disabled package count: $(dev 'pm list packages -d' | grep -c '^package:')"
echo "DNS checks (allowed host must resolve before a blocked lookup counts):"
allowed=$(dev 'ping -c1 -W2 www.youtube.com' | sed -n '1p' || true)
case $allowed in
  *"("*"0.0.0.0"*|*"("*"127.0.0.1"*|*"unknown host"*|*"cannot resolve"*|'') echo "FAIL allowed host cannot resolve"; exit 1 ;;
  *"("*")"*) echo "  allowed host resolves" ;;
  *) echo "FAIL unexpected resolver response"; exit 1 ;;
esac
blocked=$(dev 'ping -c1 -W2 softwareupdates.amazon.com' | sed -n '1p' || true)
case $blocked in
  *0.0.0.0*|*127.0.0.1*|*"unknown host"*|*"cannot resolve"*) echo "  sampled Amazon update host blocked" ;;
  *) echo "FAIL sampled update host not demonstrably blocked"; exit 1 ;;
esac
echo "LIMIT: sampled DNS results cannot rule out direct IP, IPv6, embedded DoH, first-party telemetry, or boot/wake leaks."
echo "Use router traffic capture for those checks; this script does not change VPN lockdown."
