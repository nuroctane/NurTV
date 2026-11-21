# Rebel Live: two servers, one stable address each

Rebel Live kept going down because it ran only on the cloud VM, which cannot accept incoming
connections. Its only way out is a free localhost.run tunnel, and that tunnel's hostname changes
on every restart, so the TV's provider URL broke each time. The setup is now:

| Server | Where | Address the TV uses | Up when |
|---|---|---|---|
| **Rebel Live** | Muse's cloud VM | `https://iptv.nuroctane.xyz/playlist?key=<VM key>` (after the fix below) | VM is running |
| **Rebel Live (PC)** | Docker on the home PC | `http://<PC LAN IP>:8080/playlist?key=<PC key>` | PC is on |

Both are providers in the household Lumora build, next to each other. Either one alone gives
you the channels; Sports Fallback and NFL cover the rest when both are off.

## PC server (running since 2026-11-21)

- Container `rebel-live`, image `rebeliptv/iptv:latest`, `--restart unless-stopped`,
  2 CPUs / 2 GB cap, volume `rebel-live-data`, `TZ=America/Chicago`, local stations: Chicago.
- Docker Desktop starts at login, and the container comes back with it.
- Playlist key: `private/rebel-live/api-key.txt` (gitignored). The dashboard
  (http://localhost:8080) has no login yet; it is reachable from the home network only.
- **One-time step on the PC, as Administrator** (Windows Firewall blocks the TV otherwise;
  the Ethernet network is set to Public):

  ```powershell
  New-NetFirewallRule -DisplayName "Rebel Live (LAN 8080)" -Direction Inbound -Protocol TCP -LocalPort 8080 -RemoteAddress LocalSubnet -Action Allow -Profile Any
  ```

- Reserve the PC's current LAN address in the router's DHCP settings so the address never moves.

## VM fix (for Muse to apply)

Three pieces, so a tunnel restart never reaches the TV:

1. **Stable front door.** `worker/` is a Cloudflare Worker for `iptv.nuroctane.xyz`. It reads the
   current tunnel origin from KV, passes `/playlist` and `/epg` through with every stream link
   rewritten to `iptv.nuroctane.xyz`, and 302-redirects each stream to the current tunnel. Video
   never flows through the Worker, and no key is stored in it.
   - Delete the old `iptv.nuroctane.xyz` CNAME to the dead named tunnel (`rebel-iptv`, 3fdc1414-...).
   - `wrangler kv namespace create REBEL`, put the id in `wrangler.toml`, `wrangler deploy`.
   - Create an API token with only **Workers KV Storage: Edit** on this account.
2. **Watchdog on the VM.** Copy `vm/rebel-watchdog.sh` to `~/workspace/rebeliptv/`, `chmod 700`.
   Put `CF_ACCOUNT_ID`, `CF_KV_NAMESPACE_ID`, `CF_API_TOKEN` in
   `~/workspace/rebeliptv/cloudflare.env` (mode 600, never committed). Every 60 seconds it
   restarts the server if the local playlist is empty, restarts the tunnel if the playlist through
   the tunnel is empty (the "alive but not forwarding" case), and publishes a new tunnel URL to
   KV the moment it changes. Start it at boot:
   `@reboot setsid nohup ~/workspace/rebeliptv/rebel-watchdog.sh >> ~/workspace/rebeliptv/watchdog.log 2>&1 &`
   (or Muse's own scheduler, since server and tunnel never came back by themselves after a VM restart).
3. **Auto-update bug.** `rebel-autoupdate.sh` records the new digest even when the image pull
   fails, so it never retries. Write `.installed-digest` only after the pull succeeded and the
   new binary is running and serving a playlist with channels.

After that, the TV's "Rebel Live" provider URL changes once, to
`https://iptv.nuroctane.xyz/playlist?key=<VM key>`, and never again. The household APK gets a
stage for it (like the NFL and PC stages) so the change ships in the build.

Checked locally on 2026-11-21: the Worker, run against the PC server standing in for the tunnel,
returned all 445 channels with every link rewritten, redirected a stream with 302, and
answered 503 while no origin was published.
