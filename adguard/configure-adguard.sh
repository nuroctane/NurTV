#!/usr/bin/env bash
# Applies upstreams + the pinned Roku/Amazon rules to a running AdGuard Home.
# Prompts for the admin password — never stores it.
# Usage: ./configure-adguard.sh [http://127.0.0.1:8080]
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
API="${1:-http://127.0.0.1:8080}"
LIST="$DIR/../blocklists/amazon-firetv.txt"

command -v curl >/dev/null || { echo "curl required"; exit 1; }
[ -f "$LIST" ] || { echo "missing $LIST"; exit 1; }

read -r -p "AdGuard admin user [admin]: " U; U=${U:-admin}
read -r -s -p "AdGuard admin password: " P; echo
AUTH="$U:$P"

say() { printf '\n== %s ==\n' "$*"; }
post() { curl -sS -u "$AUTH" -H 'Content-Type: application/json' -X POST "$API$1" -d "$2"; echo; }

say "status"
curl -sS -u "$AUTH" "$API/control/status" || { echo "cannot reach $API (is the container up? is the password right?)"; exit 1; }

say "upstreams (encrypted only, no ISP-plaintext DNS)"
post /control/dns_config '{
  "upstream_dns": ["https://dns.quad9.net/dns-query","tls://one.one.one.one"],
  "bootstrap_dns": ["9.9.9.10","1.1.1.1"],
  "upstream_mode": "",
  "fallback_dns": []
}'

say "pinned rules -> custom filtering rules (stored locally, no subscription)"
RULES=$(awk 'BEGIN{ORS="\n"} {gsub(/\/,"\\\\"); gsub(/"/,"\\\""); print}' "$LIST")
curl -sS -u "$AUTH" -H 'Content-Type: application/json' -X POST "$API/control/filtering/set_rules" \
  -d "{\"rules\": [\"$RULES\"]}" >/dev/null && echo "rules applied ($(awk 'NF && $0 !~ /^!/' "$LIST" | wc -l | tr -d ' ') active rules)"

say "subscriptions (refresh daily; a dead feed cannot un-block the pinned rules above)"
for url in \
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.amazon.txt" \
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.roku.txt"
do
  post /control/filtering/add_url "{\"name\":\"$(basename "$url" .txt)\",\"url\":\"$url\",\"whitelist\":false}"
done

say "verify"
curl -sS -u "$AUTH" "$API/control/filtering/status" >/dev/null && echo "filtering endpoint OK"
echo "test from this machine:  nslookup ads.amazon-adsystem.com 127.0.0.1"
