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

- `apps/home.conf`: `com.lumora` sits 5th in `apps.order`, after the four
  renamed tiles (Movies and TV, Anime, YouTube, Twitch) and before the
  webwrap tiles. No display rename — the tile reads Lumora.
- The live TV push of this entry is still pending: the TV was unreachable
  (off/asleep, no ADB/SSDP answer) when this was committed, so the repo
  change lands first and the next `provision-tv.sh` run (or a capture)
  carries it to the TV. Do not force-stop the launcher for this without
  rebinding Guard afterwards (see below).

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

- `mma-motorsports-events-2026-11-07.patch` — 23 files, +661/-47, against
  pristine v7.1 (`c0be28d`). Verified to apply cleanly. MMA reads
  API-Sports `/fights` (two fighters on a card, weight class, finish method
  instead of a score); Formula 1 reads `/races` by season, filtered to the
  day. MotoGP, NASCAR, IndyCar, WEC, WRC and Formula E join as guide-only
  sports with their own chips, icons and keywords (`ufc`, `mma`, `bellator`,
  `pfl`, `one championship`, `motogp`, `nascar`, `indycar`, `wec`, `wrc`,
  `formula e`). Event rows hide the score boxes for fights/races.
- Build instructions, key slots and the current build blocker:
  `provision/lumora/BUILD.md`.
- Until a patched build ships, the working MMA/motorsports path is
  MediaFusion (sports catalogs on) + the re-enabled live-sports scrapers
  above + ModdingCartel Live on the web.

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

1. Open Lumora → Settings → Plugins → install the 4 JS plugins from the
   store (or the staged `.js` files in `provision/lumora/plugins/`) and
   **enable each one explicitly**.
2. Settings → Plugins → paste each Stremio manifest URL from the table
   above (Cinemeta first, then Torrentio, MediaFusion, Comet, the rest).
   For AIOStreams, open the configure page and paste the manifest URL it
   generates for his config.
3. Settings → Streaming sites → re-enable Pelota Libre TV, Tv Libre Futbol,
   TvporinternetHD (and Pluto TV regions if wanted).
4. Settings → Providers → add Jellyfin `https://jellyfin.obnoxious.lol/`
   with his ModdingCartel media account; add Remux
   `https://remux.obnoxious.lol/` only if needed.
5. Paste his ObnoxiousTV manifest URL (from the Modding Cartel Discord /
   tv.obby.ca) into Settings → Plugins.
6. Enter his debrid key in Settings (one of Real-Debrid / AllDebrid /
   Premiumize / TorBox / Debrid-Link).
7. Add the epg6 guide URL as an EPG source.
8. Sports tab → tick the sports wanted; check the board fills (tells
   whether the installed build carries API-Sports keys — stock v7.1
   probably does not, so expect guide-only until a patched build ships).
9. Optional: open https://fight.nswfiles.com/ for live fights (web, not
   in Lumora).
