# AdGuard Home — TV + PS5 resolver

## Read this before pointing anything at it

This Windows box **is not always on** (last boot 2026-10-24 17:28). If the PS5's
DNS points at a machine that is asleep, PSN and game downloads fail. So:

| Consumer | Recommended resolver | Why |
|---|---|---|
| **TV (TCL_65Q650F)** | its own on-device filter (CleanTV) | survives the PC sleeping, the TV moving networks, and reboots |
| **PS5** | **AdGuard public DNS** `94.140.14.14` / `94.140.15.15` | zero infrastructure, works with the PC off |
| everything else | this local instance — **only if** it runs on an always-on box | |

Run this stack when you have an always-on host (Pi, NAS, mini-PC, or this PC left
awake), then point the router's DHCP DNS at it. Until then, it is still useful to
*see* what your devices ask for.

## Start

```sh
cd adguard
docker compose up -d
```
Then finish the wizard at <http://127.0.0.1:3000>, and apply upstreams + the
pinned list:

```sh
./configure-adguard.sh http://127.0.0.1:8080
```

## Why the rules are pinned, not subscribed

A dead or stale subscription **fails silently** in AdGuard Home: it keeps serving
the last good fetch and only writes one line to the log. `configure-adguard.sh`
therefore pushes `../blocklists/amazon-firetv.txt` into **custom filtering rules**,
which live in `conf/AdGuardHome.yaml` on disk. A network/feed outage cannot
silently un-block the TV.

## What NOT to block

`blocklists/amazon-firetv.txt` carries an explicit DO NOT BLOCK section:
`aiv-cdn.net`, `aiv-delivery.net` (Prime Video 4K), `atv-ps.amazon.com`
(Appstore/entitlements). Blocking those costs you 4K playback and app installs.

## Fire OS leaks DNS

Fire OS injects `net.dns3=8.8.8.8` regardless of configured DNS. Router-level
action needed for full coverage:

1. NAT-redirect outbound TCP/UDP **53** to this host.
2. Reject outbound **853** (DoT).
3. Reject **443** to public DoH bootstrap IPs (1.1.1.1, 8.8.8.8, 9.9.9.9, dns.google).

Without step 1 the TV can bypass this resolver entirely.
