#!/usr/bin/env bash
# rebel-watchdog.sh: keeps Rebel Live on the VM serving, and keeps the stable front door
# (Cloudflare Worker at iptv.nuroctane.xyz) pointed at the current tunnel.
#
# Every 60 s:
#   1. server check: local /playlist?key= must list > 50 channels, else restart the server
#   2. tunnel check: the same playlist through the tunnel must list > 50 channels
#      (catches the "process alive but not forwarding" failure), else restart the tunnel
#   3. publish: whenever the tunnel URL differs from the last one published, write it to KV
#
# Start once, and on every VM boot (cron @reboot or Muse's scheduler):
#   setsid nohup ~/workspace/rebeliptv/rebel-watchdog.sh >> ~/workspace/rebeliptv/watchdog.log 2>&1 &
# Never prints the API key or the Cloudflare token.
set -u
R=${REBEL_DIR:-$HOME/workspace/rebeliptv}
KEY=$(cat "$R/api-key.txt")
CF_ENV="$R/cloudflare.env"   # CF_ACCOUNT_ID, CF_KV_NAMESPACE_ID, CF_API_TOKEN (KV write only), mode 600
LOCK="$R/.watchdog.lock"
exec 9>"$LOCK"; flock -n 9 || { echo "watchdog already running"; exit 0; }

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
count() { curl -s -m 25 "$1/playlist?key=$KEY" 2>/dev/null | grep -c '^#EXTINF' || true; }
tunnel_url() { tr -d ' \r\n' < "$R/tunnel-url.txt" 2>/dev/null; }

restart_server() {
  log "server unhealthy; restarting"
  pkill -f "$R/rootfs/app/iptv" 2>/dev/null; sleep 2
  setsid nohup "$R/rebel-up.sh" >> "$R/rebel-up.log" 2>&1 &
  sleep 20
}

restart_tunnel() {
  log "tunnel unhealthy; restarting"
  pkill -f lhr-pty.py 2>/dev/null; pkill -f lhr-ssh.sh 2>/dev/null; sleep 2
  : > "$R/tunnel-url.txt"
  setsid nohup "$R/lhr-up.sh" >> "$R/lhr-up.log" 2>&1 &
  for _ in $(seq 1 30); do [ -n "$(tunnel_url)" ] && break; sleep 2; done
}

publish() {
  [ -f "$CF_ENV" ] || { log "no cloudflare.env; skipping publish"; return 1; }
  # shellcheck disable=SC1090
  . "$CF_ENV"
  curl -s -m 30 -X PUT \
    "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces/$CF_KV_NAMESPACE_ID/values/origin" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: text/plain" \
    --data-binary "$1" | grep -q '"success":true'
}

last=""
while true; do
  [ "$(count http://127.0.0.1:8080)" -gt 50 ] || restart_server
  t=$(tunnel_url)
  if [ -z "$t" ] || [ "$(count "$t")" -le 50 ]; then
    restart_tunnel; t=$(tunnel_url)
  fi
  if [ -n "$t" ] && [ "$t" != "$last" ]; then
    if publish "$t"; then log "published new tunnel origin"; last=$t; else log "publish failed; retrying next pass"; fi
  fi
  sleep 60
done
