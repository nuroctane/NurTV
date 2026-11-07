# Lumora provisioning (com.lumora, v7.1)

Lumora is the live-TV/plugin shell on the working TV, installed 2026-11-07
from the verified v7.1 release asset. It is a player, not a provider: it
ships no channels. Sources are Xtream Codes, M3U/M3U8, Stalker Portal,
Jellyfin, Emby, Silo and Plex, plus a JS plugin engine and Stremio add-ons
under Settings → Plugins. Licence is PolyForm Noncommercial 1.0.0 — fine for
personal use, not OSI open source; do not rebrand it.

Full research (sources, plugins, add-on catalogues, sports-tab internals):
`~/workspace/tv-lumora/lumora-plugins-sources-2026-11-07.md` (local scratch,
not in this repo). obnoxious.lol integration research:
`~/workspace/tv-lumora/obnoxious-lol-integration-2026-11-07.md`.

## Patched build installed (2026-11-07)

- Package `com.lumora`, versionName 7.1, **versionCode 71001** (patched build line).
- **Build 7 (2026-11-07, ~16:30–17:00 CT, his PC, Grok Build on the VM driving):** `BUILD_EXIT=0` on the second assemble (5m 3s). The first assemble failed in 2m 32s on three compile errors in the new EPG resolver (`XmltvChannel` unqualified — it only exists as `XmltvParser.XmltvChannel`); the two signatures were qualified, the patch regenerated, rebuilt once, green. Unit-test gate skipped per his order on this job. APK `C:\Users\david\Scripts\lumora-work\lumora-patched-7.1.apk`, 39,954,802 bytes, sha256 `84229b1812f2447a54d98b5a0ff47d2da60013848a0c9e52c1493583380d32b6` (differs from build 6's `af21e4ff…`, as it must — the code changed). Same signing key, installed 2026-11-07 ~17:00 CT via `adb install -r` (Success), data preserved.
- **Build 7 fixes:** (1) Samsung TV Plus playback — `StreamContentSniffer.shouldProbe()` now also probes extensionless URLs (except bare Xtream/Stalker `/live|/movie|/series` panel links), so Samsung `jmp2.uk/stvp-*` HLS streams get a manifest type instead of falling back to progressive extractors (`UnrecognizedInputFormatException` in build 6). (2) EPG matching — new `FeedChannelResolver` in `EpgChannelMapping.kt` ranks feed channels (exact tvg-id, then id base, then exact first display name, then normalised name, then exact secondary name) with per-target best-winner eviction, and excludes known-bad feed ids `ufc.us` and `ufc.uk` (verified live in the epg6 feed: `ufc.us` carries ¡Hola! TV Spanish lifestyle data, `ufc.uk` is 47 placeholder rows titled literally "UFC", `ufc6.us` is all-day "No EVENT Today" blocks). No upstream report filed, per his decision. Verified live after install: zero parse errors in logcat across all five playback taps; Samsung NASCAR, Pluto NFL Channel (one failover, then ~3 min play), NHL Network, beIN Sports USA and beIN XTRA (failover, then 4K HW AVC ~4 Mbps sustained) all play; UFC HLS plays in fullscreen (HW AVC 1280x720, ~3.7 Mbps) once the relay went live at ~17:14 CT. UFC guide rows rewritten by the new resolver: 0 "No EVENT Today" rows in the DB, UFC channel shows only genuine UFC programming ("UFC Fight Flashback", "UFC Main Event", "100 UFC Submissions!").
- Release is **debuggable on purpose**: it lets the app private data be provisioned with `adb shell run-as` instead of hand-driving the UI. Single-user TV build, never shipped to a store.
- Installed 2026-11-07 14:05:50 CT via `adb install -r` (Success) — an in-place upgrade over the earlier patched build, same signing key, data preserved (`firstInstallTime` still 2026-11-07 13:15:21). Build 5 was the first patched build, installed as a fresh install (stock 7.1 uninstalled first; a new signing key cannot upgrade stock in place, so stock data was wiped and provisioning redone). Install date and hash recorded here; the APK binary itself is not committed to this repo.
- The patch in this folder is now 45 files, +2114/-63, against pristine v7.1 (`c0be28d`), regenerated from the fork before build 7. It adds the MMA/motorsports sports section, a built-in IRC client (below), and the live-edge player recovery (below), plus the build-7 Samsung playback probe fix and the EPG `FeedChannelResolver` (above).

## What was provisioned live (2026-11-07, via run-as file push)

- JS plugins: torrent-search, reddit-iptvscan and anime-senshi installed and explicitly enabled; scraper-sites.js installed as registry data (not runnable).
- 9 Stremio add-ons installed and explicitly enabled: Cinemeta, Torrentio, MediaFusion (configured manifest, sports catalogs on — Fighting WWE/UFC, Formula Racing, MotoGP, Live TV PPV, UFC Fight Pass, DAZN, ESPN Plus), Comet, WatchHub, OpenSubtitles v3, Anime Kitsu, Anime Catalogs, ObnoxiousTV (per-member manifest, supplied by the user; no URL recorded anywhere).
- Live-sports scraper re-enable NOT confirmed: Pelota Libre TV, Tv Libre Futbol, TvporinternetHD toggles live in the app DB, not prefs files, so they could not be flipped from the shell. His tap in Settings → Streaming sites.
- Launcher: `apps/home.conf` pushed live, com.lumora 5th, launcher restarted, Guard rebound.
- Not installed: epg6 guide source (no `sqlite3` binary on the TV, so the row could not be inserted; his tap in Settings → Lists → EPG sources). AIOStreams (needs his browser configure step; functionally covered by Torrentio + MediaFusion + Comet). Jellyfin provider (needs his ModdingCartel media account). Debrid key (none supplied). API-Sports keys (none supplied; MMA/F1 boards run guide-only).

## What was provisioned live, build 7 (2026-11-07, via run-as file push)

- Four IPTV providers added earlier in the day and still in prefs: iptv-org sports (479 in / 464 live out), Samsung TV Plus US (593 channels), Pluto TV US (458 channels), NHL Network and beIN XTRA as one-entry M3U wraps. Catalog after all six providers (incl. UFC): 1,471 in / 1,288 live out.
- UFC HLS provider (`provision/lumora/ufc.m3u`, two entries UFC + UFC Mirror, group Sports) pointing at the raw GitHub URL; favorited. The relay serves a real playlist once a UFC event goes live (verified 365-byte HLS manifest at 17:16 CT); before that it returns 200 with a 0-byte body.
- EPG source "Curated M3U guide (epg6)" inserted in `lumora.db` (2026-11-07 15:11 CT, 7,715 programmes / 96 channels at first sync). After the build-7 install the guide re-synced under the new resolver: 19,563 programmes across 534 channels, auto-refreshes every 4h. The UFC channel's old 3-way name merge (ufc.us ¡Hola! data + ufc6.us "No EVENT Today" + 400000106 genuine UFC) is gone — verified in the DB (0 "No EVENT Today" rows) and on screen (UFC row shows "UFC Fight Flashback" / "UFC Main Event" only).
- Favorites expanded 2026-11-07 ~17:15 CT from 46 URLs to **92 URLs** (84 distinct channels in the left rail after dedupe): all MMA/UFC/Bellator/PFL/ONE, F1/MotoGP/NASCAR/IndyCar/motorsports, NFL Channel + NFL Network, college football (ESPNU, ACC, Big 12, Pac-12), NBA Channel + NBA TV, MLB + MiLB, NHL Network, beIN XTRA + soccer, boxing (DAZN Ringside, Top Rank, Zuffa Boxing), WWE/TNA. Existing favorites kept, none orphaned. Dead-marks cleared with the push (10 new ones from the playback taps were in the old prefs; the new prefs carry none).
- Pluto/Amagi playback mechanism: NOT established as a code issue. Pluto NFL and the Amagi channels (NHL, beIN XTRA) failed in build 6 with `UnrecognizedInputFormatException` on valid `.m3u8` manifests; a dedicated live investigation was blocked (TV unreachable at the time, no logcat). In build 7 they play (see above) — the Samsung probe fix plus the version-switching failover covers them. No code change was forced for them.

## Built-in IRC client (Modding Cartel fight chat)

- Native Kotlin client inside Lumora, Views/XML, no Compose. Connects to `irc.obnoxious.lol:6697` TLS, trusted certificates only, no server password. Nick configurable in the chat view, default `nuroctane`.
- Two ways in: an MMA event offers Fight chat (titled with the fight), and a Fight chat tile in the player options panel overlays playback (Back closes the panel first).
- Channel is configurable and defaults to blank on purpose: the fight site never publishes the channel name in any page or bundle it serves, so the first open asks for it once and remembers it. He reads it off The Lounge at chat.obnoxious.lol.
- UI patterns adapted from IRCCloud for Android (Apache-2.0): RecyclerView message list, one deterministic colour per nick, timestamps, auto-scroll only while already at the bottom. Revolution IRC (GPL-3.0) was studied for UX behaviour only; none of its code is copied.
- Open item: TCP connects to irc.obnoxious.lol on 6697/6666 timed out from his residential IP on 2026-11-07 (80/443 fine), so the native client may not connect until the server side allows external clients or the daemon is up. The client reconnects with backoff and shows status; it is built, not yet proven live.

## Player

- Lumora already played via Media3/ExoPlayer with HLS/DASH, fast-zap LoadControl, track picker, sidecar subtitles, external-player handoff and a torrent engine, so that base stayed. One proven piece adopted: behind-live-window recovery from the Media3 demo app (Apache-2.0). A live HLS stream that falls behind its playlist window now seeks to the default position and prepares instead of running the generic failover, which replayed the same URL from position 0 and errored again. mpv-android and VLC are whole GPL engines and were not adopted as pieces.

## Install source (provision)

- Package `com.lumora`, version 7.1 (versionCode 71).
- APK: `apps/lumora-7.1.apk`, sha256
  `5c66032eb9053e0c9e0a31e9e4ace9debbe4ee77f89eb4266467b474408a204a`
  (matches the digest GitHub publishes for the v7.1 `Lumora.apk` asset).
- `provision/golden-state.json`: `check: presence` — the version is **not**
  pinned (Golden State policy: only the CleanTV launcher carries a version).
  Provision installs from the repo APK when the package is missing and leaves
  an installed copy alone at any version.
- Downloader code: 9528194. Upstream: https://github.com/LumoraPlayer/Lumora

## Launcher wiring

- `apps/home.conf`: `com.lumora` sits 2nd in `apps.order`, right after Movies and TV (`st.atlantic.app`), everything else after it in current order. Display-renamed to **Sports** (`name.com.lumora=Sports`) with a sports logo (football, basketball, baseball bat, boxing gloves) as `apps/art/com.lumora.png` (2026-11-07, NurTV `4c8dabc`).
- The live TV push of this entry is done: pushed 2026-11-07, launcher restarted, Guard rebound.

## JS plugins (official store, 4 scripts only)

Store index:
`https://raw.githubusercontent.com/LumoraPlayer/Lumora-Plugins/master/scripts/index.json`
Install: Settings → Plugins → browse the store, or fetch the `.js` URL.
Every script needs an **explicit enable** after install — install alone does
not switch it on. Staged copies live in `provision/lumora/plugins/` so they
can be sideloaded/imported without re-fetching; verify the hash before use.

| ID / file | What it does | Capability | sha256 |
|---|---|---|---|
| Anime (Senshi) — `anime-senshi.js` | AniList search + streams from senshi.live, sub/dub | stream_search | `e31d9260af7746fe829582fb1170fc997a8098fd3b86c04160a9b0e82a7e17eb` |
| Torrent Search — `torrent-search.js` | Searches public torrent indexers (ThePirateBay, Knaben); Lumora's built-in torrent engine streams | stream_search | `b9325a76b38e86c0c7a24a06c28b1d8e4751c04cd1301550c85cd85a9e26a0c9` |
| Reddit IPTV Scanner — `redditscan.js` | Scans r/IPTV_ZONENEW for public IPTV credential pastes, live-tests them, proposes working ones; only accepts providers carrying Sky Sports | provider_discovery | `ff63f0ceb57e9c4570ca75216f8df57e3b19b6cd2f6bc3e7fa411d2277feca0a` |
| Streaming Site List — `scraper-sites.js` | **Data only.** Which built-in scraper sites are live and where the repointable ones point | scraper_sites | `734acfc035d14673d4fcb248540b01851617b83e2721866b5e3e5e929b4dcb50` |

No other JS plugins were found anywhere as of 2026-11-07. Do not invent a
community store URL. Reddit IPTV Scanner proposes shared/stolen logins —
treat anything it finds as untrusted.

## Stremio add-ons (install by manifest URL in Settings → Plugins)

Install order: Cinemeta first (metadata backbone), then the stream engines.

| Add-on | Manifest URL | Notes |
|---|---|---|
| Cinemeta v3.0.12 | https://v3-cinemeta.strem.io/manifest.json | Official catalogs + metadata |
| WatchHub v1.15.0 | https://watchhub.strem.io/manifest.json | Where-to-stream lookup |
| OpenSubtitles v3 | https://opensubtitles-v3.strem.io/manifest.json | Subtitles (also native in Lumora) |
| Torrentio v0.0.15 | https://torrentio.strem.fun/manifest.json | Configure: https://torrentio.strem.fun/configure — filter providers/quality, add a debrid key |
| MediaFusion | https://mediafusion.elfhosted.com/manifest.json | Configure: https://mediafusion.elfhosted.com/configure — **turn the sports catalogs on** (UFC/WWE, F1, MotoGP live sports); live TV; debrid key for cached torrents |
| Comet v2.0.0 | https://comet.elfhosted.com/manifest.json | Configure: https://comet.elfhosted.com/configure — fastest torrent/debrid search |
| AIOStreams | No fixed public manifest — configure at https://aiostreams.elfhosted.com/stremio/configure, which generates a per-config manifest URL (`https://aiostreams.elfhosted.com/stremio/<uuid>/manifest.json`) | Aggregator (Torrentio + MediaFusion + Comet etc. in one endpoint, one debrid key). The free ElfHosted instance does **not** bundle Torrentio |
| Anime Kitsu | https://anime-kitsu.strem.fun/manifest.json | Kitsu anime catalogs + subtitles |
| Anime Catalogs | https://1fe84bc728af-stremio-anime-catalogs.baby-beamup.club/manifest.json | Anime catalogs from MAL, AniDB, AniList, Kitsu |
| Plexio | https://plexio.stream/manifest.json | Only if a Plex server exists to point it at (Lumora already speaks Plex natively) |
| StreamBridge: Emby to Stremio | https://39427cdac546-streambridge.baby-beamup.club/manifest.json | Only if an Emby server exists (Lumora already speaks Emby natively) |

Not provisionable: TorBox's Stremio add-on has no public manifest (per-user
URL from a TorBox account — TorBox is a debrid service first, native in
Lumora's DebridManager); SeaDex's checked host 404s; the "Sports Streams"
listing exposes no verified manifest URL; StreamSports99 and
SeriousSportsSync are self-host only.

## Built-in site sources (already in the APK — toggle, do not install)

74 registered entries in `Provider.providers` (63 distinct providers).
51 enabled, 16 kill-switched in the store's `scraper-sites.js` data file.
Toggle per-site in **Settings → Streaming sites**.

Kill-switched right now — re-enable per-site if wanted:

- **Pelota Libre TV, Tv Libre Futbol, TvporinternetHD** — live sports
  streams. This is the working live-sports path until the MMA/motorsports
  code change ships as a build.
- Pluto TV ×7 regions, CableVisionHD, IPTV Spain, IPTV-All World, MAGISTV,
  AfterDark, 1Jour1Film.

## EPG

One-tap curated guide (its tvg-ids are iptv-org names, which is what the
sports channel matcher is tuned against):

`https://github.com/ferteque/Curated-M3U-Repository/raw/refs/heads/main/epg6.xml.gz`

Add as an EPG source. The sports board reads the guide for guide-only
sports, so the channels carrying UFC/F1/MotoGP need to be in it.

**Done 2026-11-07:** the epg6 source row was inserted directly in
`lumora.db` (no sqlite3 on the TV, so the EPG agent did the insert with a
pulled/pushed DB copy). First sync 15:11 CT: 7,715 programmes / 96
channels. After the build-7 install it re-synced under the new resolver:
19,563 programmes / 534 channels, auto-refresh every 4h. No upstream
report was filed about the feed's UFC mapping, per his decision — the fix
is fork-side only (see the build-7 note above).

## Debrid (built in — his account + key, never committed)

Real-Debrid, AllDebrid, Premiumize, TorBox, Debrid-Link — all five in
`debrid/DebridManager.kt`. Enter the key in Settings. No debrid account is
bundled. This is what makes torrent streams instant instead of slow.

## obnoxious.lol integration (ModdingCartel)

- **Jellyfin server (native Lumora provider):** `https://jellyfin.obnoxious.lol/`
  — Settings → Providers → Jellyfin, password or Quick Connect. Needs his
  community-issued ModdingCartel media account. No plugin, no manifest.
- **Remux backend (second Jellyfin-type provider slot):**
  `https://remux.obnoxious.lol/` — Jellyfin-compatible API. Add only if the
  Jellyfin server above does not carry everything.
- **ObnoxiousTV (private Stremio add-on):** setup at https://tv.obby.ca/ —
  "Everything. One addon." Membership-gated: the manifest URL is issued per
  Discord member via the Modding Cartel Discord. **No public manifest URL
  exists and none is recorded here.** He pulls his from the Discord /
  tv.obby.ca setup flow and pastes it into Settings → Plugins. Once he has
  it, installation is one paste, no keys, no config.
- **ModdingCartel Live (fight watcher, NOT a Lumora add-on):**
  https://fight.nswfiles.com/ — web-based live fight watcher. The working
  live-MMA path today; a candidate webwrap tile or link from the sports
  section, not a Lumora install.
- Jellyflix (https://jellyflix.app/) is a separate Jellyfin client, not a
  Lumora extension — skip it for this job.
- Trust note: files.obnoxious.lol scores 25/100 on Gridinsoft and is
  blacklisted by several security vendors. Treat the file-hosting side as
  untrusted; the media/Jellyfin side is a separate, member-gated service.

## MMA + motorsports event section (code change, not config)

MMA does not exist in stock Lumora at all and motorsports beyond F1 do not
either — there is no `MMA` entry in the `Sport` enum, and the guide keywords
`motogp`/`motorsport` are mapped onto Formula 1. The patch in this folder
adds them the same way the existing sports are wired:

- `mma-motorsports-events-2026-11-07.patch` — 45 files, +2114/-63, against
  pristine v7.1 (`c0be28d`). Installed as versionCode 71001 on 2026-11-07
  (build 6, then build 7 with the Samsung probe fix and EPG resolver — see
  "Patched build installed" above). MMA reads
  API-Sports `/fights` (two fighters on a card, weight class, finish method
  instead of a score); Formula 1 reads `/races` by season, filtered to the
  day. MotoGP, NASCAR, IndyCar, WEC, WRC and Formula E join as guide-only
  sports with their own chips, icons and keywords (`ufc`, `mma`, `bellator`,
  `pfl`, `one championship`, `motogp`, `nascar`, `indycar`, `wec`, `wrc`,
  `formula e`). Event rows hide the score boxes for fights/races.
- Build instructions, key slots and the current build blocker:
  `provision/lumora/BUILD.md`.
- A patched build is installed (see "Patched build installed" above).
  MediaFusion (sports catalogs on) + the live-sports scrapers (re-enable
  unconfirmed, see above) + ModdingCartel Live on the web remain the working
  path for streams until a keyed build ships.

## Guard rebind (launcher restarts)

Any launcher force-stop/restart **must** rebind Guard afterwards, or HOME
breaks:

```sh
adb shell settings put secure enabled_accessibility_services tv.cleantv.home/tv.cleantv.home.Guard
adb shell settings put secure accessibility_enabled 1
```

A plain `am start` does not rebind it. `provision-tv.sh` already does this
after its launcher restart step.

## Live steps remaining (his taps in the app — not faked, not done)

Done live on 2026-11-07 and struck from this list: the 3 runnable JS plugins
installed and enabled, the 9 Stremio add-ons installed and enabled
(including ObnoxiousTV from his per-member manifest), home.conf pushed,
the epg6 guide source inserted and synced (19,563 programmes / 534
channels), the UFC HLS channel in Lumora and playing, favorites expanded
to 92 URLs. What is left:

1. Settings → Streaming sites → re-enable Pelota Libre TV, Tv Libre Futbol,
   TvporinternetHD (toggles live in the app DB, unconfirmed from the shell).
2. Settings → Providers → add Jellyfin `https://jellyfin.obnoxious.lol/`
   with his ModdingCartel media account; add Remux
   `https://remux.obnoxious.lol/` only if needed.
3. Enter his debrid key in Settings (one of Real-Debrid / AllDebrid /
   Premiumize / TorBox / Debrid-Link).
4. For AIOStreams, open the configure page and paste the manifest URL it
   generates for his config.
5. Sports tab → tick the sports wanted; check the board fills (no
   API-Sports keys in this build, so expect guide-only for MMA/F1 until a
   keyed build ships).
6. Fight chat: open an MMA event → Fight chat, enter the channel name once
   (read it off The Lounge at chat.obnoxious.lol).
