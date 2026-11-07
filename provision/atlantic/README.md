# Atlantic — Lumora source match (researched 2026-11-07)

**Verdict up front: almost nothing from the Lumora list ports into Atlantic, and that is an architecture fact, not a lack of trying.** Atlantic's sources are compiled into a first-party plugin APK, hash-verified and host-cert-verified, and they resolve through the author's private backend. There is no open extension surface to add to. What follows is the evidence, the full match table, and the levers that actually exist.

## Atlantic's extension system (read from the installed APK, not guessed)

- **App:** `st.atlantic.app`, v1.0.10 / versionCode 14, `com.zstream.android`, on the TCL Fire TV. Repo named in the APK: https://github.com/zstream-mov/Android — **that repo does not resolve (404 / not found)** as of 2026-11-07, so no source was read from it. Everything below is from the installed APKs themselves.
- **Atlantic is a P-Stream-style fork** (zstream.mov links the p-stream repo). It is a TMDB-fronted movies/series app. `MediaRequest.Type` is only `MOVIE` / `SHOW`. No live TV, no sports, no EPG, no guide.
- **The "plugin" is a single first-party APK, not a plugin system.** Manifest: https://atlantic.st/dl/plugin/manifest.json — latestVersion 9, displayVersion 1.0.8, downloadUrl https://atlantic.bz/dl/plugin/plugin-v9.apk, sha256 `a1fc2a670e73cd4a7ab7a80687b6e25a8a5f196f58ad97f71208cdc1dc167ccf`. Downloaded 2026-11-07 and **hash verified exact**.
- **Plugin contents (plugin-v9.apk, 5,273,136 bytes):** one dex, 22 hardcoded Kotlin sources, each a class implementing the plugin `Source` contract, plus native lib `libzstream-crypto.so` (arm64 + armv7). Sources resolve "natively": the plugin sends a `MediaRequest` (tmdbId, type, season/episode, title, year) and the resolution happens through encrypted native calls against the zstream.mov backend (Origin/Referer `https://zstream.mov`). The underlying sites are not in the plugin — they are server-side.
- **The 22 sources in plugin v9** (id → display name): aether → Aether [4K], amethyst → Amethyst (4K), aphrodite → Aphrodite, apollo → Apollo, artemis → Artemis [4K], aspera → Ardua, aurora → Aurora API, cosmic → Cosmic, dizipal → Dizipal, eclipse → Penumbra, fuji → Fuji, halcyon → Halcyon, lumi → Lumi [4K], magnolia → Camellia, nepu → Nepu, nesterov → Perigee, nexus → Nexus (DDL), shibuya → Shibuya, stellar → Nebula, thalia → Thalia, tokyo → Tokyo, valley → Canyon [4K HDR].
- **Nepu is gated on the app version:** `NepuSource` contains "Nepu needs a newer app version". The app manifest (https://atlantic.st/dl/app/manifest.json) now lists **v1.0.11** (latestVersion 10011, downloadUrl https://atlantic.bz/dl/app/atlantic-v1.0.11.apk, size 22,772,725). The TV is on v1.0.10. App updates are frozen at nur's order — v1.0.11 is NOT installed here.
- **Trust chain (why you cannot just add a source):**
  - The app hash-checks the plugin against the manifest on download ("Plugin hash mismatch after download"). A modified plugin APK is rejected.
  - The plugin verifies the host app's signing certificate (SHA-256 `284cb87f31d7c73ff61599792ebe3c3a87941ed5beb821f6b64ff24d7999eb17` pinned in `HostVerifier`) — the plugin only runs inside genuine Atlantic.
  - There is no custom plugin/manifest URL setting, no "add source", no repository UI, no exported component for provisioning (manifest: single MainActivity, leanback launcher only; http/https VIEW intents only).
  - `allowBackup=false`, `/data/data/st.atlantic.app` unreadable via adb shell, `run-as` fails (not debuggable). The plugin lives in private `files/atlantic-plugin/` (with `atlantic-plugin-dex` and `atlantic-plugin-native/`). **Nothing in Atlantic's private data can be read or written from code on this non-rooted TV.** The installed plugin version is therefore not verifiable from code; the app checks for plugin updates at launch and plugin updates always run (per his Nov 2 order), so the installed plugin is almost certainly v9 already, and the app was launched 12:26 today and is running with no plugin errors in the visible log.
- **Source order is user-configurable in-app only:** `reorderSources` / `enableSourceOrder` / `enable_last_successful_source` settings exist; the order (`storedOrderJson`) lives in private prefs. Default order from `SourceOrderKt`: magnolia, eclipse, stellar, nesterov, valley, aether, lumi, aspera, tokyo. Cannot be set from code.
- **What Atlantic already has built in:** TMDB metadata, Trakt + Simkl repositories, AniList anime metadata (`AniCard`/`AniMedia`), OpenSubtitles + SubDL + SubSource subtitle APIs, IntroDB + AniSkip skip segments, Real-Debrid token slot (`debridService`/`debridToken`), downloads, local-library folders. M3U strings in the APK are ExoPlayer HLS playlist parsing only — there is no M3U playlist import.

## Match table — Lumora list vs Atlantic

### Already has (skip — no action)

| Lumora item | Atlantic equivalent |
|---|---|
| OpenSubtitles v3, SubDL, SubSource (subtitle addons) | Built in: `api.subdl.com`, `rest.opensubtitles.org`, `api.subsource.net` |
| Trakt, Simkl | Built-in repositories, in-app sign-in |
| TMDB metadata / Cinemeta role | Built-in TMDB (`api.themoviedb.org`) |
| Anime catalogs (Kitsu, Anime Catalogs, Anime Seasons) | Built-in AniList metadata + anime sources in the plugin (Tokyo, Shibuya, Fuji, Nepu when unlocked) |
| Intro skip / AniSkip | Built in (IntroDB + AniSkip APIs) |
| Debrid (Real-Debrid etc.) | Slot exists (`debridService`/`debridToken`) — needs his key, see "waiting on him" |

### Does not fit Atlantic at all (do not force)

| Lumora item | Why it does not fit |
|---|---|
| All Stremio addons (Torrentio, MediaFusion, Comet, AIOStreams, Cinemeta, WatchHub, ObnoxiousTV, Plexio, StreamBridge, anime catalog addons, subtitle addons) | Atlantic has **no Stremio addon client**. No "stremio" string anywhere in the APK. There is nowhere to paste a manifest URL. ObnoxiousTV specifically: its manifest is a Stremio manifest; Atlantic cannot consume it. (Its per-member URLs were not written anywhere in this job.) |
| All 4 JS plugins (Anime Senshi, Torrent Search, Reddit IPTV Scanner, scraper-sites.js) | Atlantic has **no JS plugin engine**. Its plugin is compiled Kotlin + native crypto. No QuickJS, no script loading. |
| Built-in site scrapers (SFlix, Ridomovies, CineLite, NetPrime, MStream, etc. — 74 Lumora sources) | Atlantic's sources are server-side resolvers in the author's plugin, not site scrapers. There is no per-site toggle or scraper registry to add to. |
| Live TV / sports (MediaFusion sports, Pelota Libre, Tv Libre Futbol, TvporinternetHD, Pluto TV, Vavoo, StreamSports99, SeriousSportsSync, epg6, API-Sports) | Atlantic is **MOVIE/SHOW only**. No live TV, no sports tab, no EPG, no guide. Nothing to wire these into. |
| M3U / Xtream / Stalker / Jellyfin / Emby / Plex / SMB / WebDAV providers | No such provider types exist in Atlantic. |
| Reddit IPTV Scanner | No IPTV provider type to feed. |
| Torrent Search / torrent engine | No torrent engine in Atlantic. |

### The one thing that would add a source — gated by his own freeze

- **App v1.0.11** is available from the official manifest and **Nepu needs it** ("Nepu needs a newer app version"). v1.0.11 may carry more than Nepu. App updates are frozen at his order (Background app update checks OFF, REQUEST_INSTALL_PACKAGES ignore). **Not installed.** If he lifts the freeze, updating the app is the only way a new source arrives — and it arrives from the author, not from us.

## What was actually provisioned into Atlantic on the TV

**Nothing was added, removed, or modified in Atlantic.** That is the honest result: there is no provisionable surface, and forcing one would mean modifying a hash-verified plugin (rejected on next check) or touching the APK (frozen at his order). Atlantic was verified running (PID 18389, launched 12:26 today, MainActivity `com.zstream.android.MainActivity`), plugin manifest reachable, plugin v9 hash verified, app untouched at v1.0.10.

## What makes Atlantic feel unlimited (the real levers, in order)

1. **v1.0.11 update** — lifts the Nepu gate and whatever else the author shipped. Waiting on him to lift the app-update freeze. Do not do this unilaterally.
2. **Real-Debrid token** — the slot is already in the app; a key unlocks cached/debrid streams for the existing 22 sources. Waiting on his key (he declined debrid for Lumora; Atlantic is a separate decision).
3. **Trakt / Simkl sign-in** — in-app, his call; syncs Continue Watching/watched.
4. **Source order in-app** — Settings → Sources: reorder the 22 sources, enable "last successful source". 30 seconds in the app UI; cannot be done from code (private prefs unreadable).
5. **The plugin self-updates** — plugin checks run at launch and always run; new sources the author ships arrive as plugin updates, no action needed.

## Rollback / safety

- The pulled v1.0.10 APK from the TV (`atlantic-base.apk`, 22,772,725 bytes, versionName v1.0.10 verified via `dumpsys package`) is kept as the rollback copy — this matters because the official app manifest now serves v1.0.11, so v1.0.10 is no longer downloadable from the official source. Stored in the NurTV repo as `apps/atlantic-1.0.10.apk`.
- The plugin re-downloads from the official manifest (hash-verified) if ever lost, so no plugin backup is needed.
- No Atlantic data was read, written, cleared, or backed up (impossible via adb: `allowBackup=false`, private dir unreadable). Nothing to roll back on the TV because nothing was changed.

## Sources

- Installed APK pulled from the TV 2026-11-07 (`st.atlantic.app`, v1.0.10 vc14); plugin manifest + plugin-v9.apk fetched live and hash-verified 2026-11-07.
- https://atlantic.st/dl/plugin/manifest.json, https://atlantic.st/dl/app/manifest.json
- ~/workspace/tv-lumora/lumora-plugins-sources-2026-11-07.md, ~/workspace/tv-lumora/obnoxious-lol-integration-2026-11-07.md
- https://github.com/zstream-mov/Android — does not resolve (404) as of 2026-11-07; not used.

## 2026-11-07 - Updated to v1.0.11 (in place)

- Updated Atlantic st.atlantic.app from v1.0.10 to v1.0.11 (versionCode 15) via adb install -r only. No uninstall, no clear, profile/sign-ins/settings/plugins preserved (firstInstallTime 2026-10-25 unchanged, lastUpdateTime 2026-11-07 13:13:32).
- Update freeze lifted for the install only (REQUEST_INSTALL_PACKAGES allow), then re-applied (ignore). In-app background update check toggle stays OFF (UI-only, cannot be flipped from code).
- Nepu source is gated on the app version ('Nepu needs a newer app version'); with v1.0.11 installed the gate is lifted. Whether Nepu shows in the source list is confirmed live by nur (source list lives in private prefs).
- Rollback remains apps/atlantic-1.0.10.apk.
