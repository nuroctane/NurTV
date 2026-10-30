# PS5 + AdGuard — decided 2026-10-25

## Decision: AdGuard public DNS, not the local resolver

This network has **no always-on host**. A desktop that sleeps cannot be a DNS
server for a console: an unreachable resolver is indistinguishable from broken
internet, and on a PS5 it presents as PSN being down plus failed game downloads.

So the PS5 uses AdGuard's public resolver, which needs no infrastructure on this
LAN and keeps working with every machine here powered off.

## Steps (on the console)

1. `Settings → Network → Settings → Set Up Internet Connection`
2. Pick your network (Wi-Fi or LAN)
3. Press **Options (⋯)** → **Advanced Settings**
4. **DNS Settings → Manual**
5. Primary `94.140.14.14` · Secondary `94.140.15.15`
6. Back out → **Test Internet Connection**

Fast path if it misbehaves: set DNS back to **Automatic**. Nothing else on the
console depends on this.

## What this does and does not do

**Does:** blocks ad/tracking third parties the console reaches, for every
device-agnostic domain in AdGuard's public blocklist.

**Does not:** remove PS5 home-screen promotional tiles, "Explore", or news cards.
Those are served from Sony first-party Store/PSN domains. Blocking them breaks
the Store, PS Plus and game patches. There is no PS5 ad blocker and no PS5 root.

## Also worth doing (free, no DNS involved)

- `Settings → Users and Accounts → Privacy` — restrict what Sony may collect
- System error reporting / usage sharing → off

## Why not the local AdGuard Home

`adguard/` stays in the tree as a **lab** option. It becomes the right answer only
if this network gains an always-on box (Pi, NAS, mini-PC) — then point the router's
DHCP DNS at it and add the Fire OS hijack rules in `adguard/README.md`.
