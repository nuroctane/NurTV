# Apps — TCL_65Q650F (hazel / AFTMD001, Fire OS 7.7.1.7)

Current inventory: SmartTube, S0undTV, Kick, Rumble, X, Atlantic, SozoTV,
X-plore, Aerial Views, ARVIO, CloudStream, Lumera, Watchbox, Zangetsu, CleanTV,
personalDNSfilter, Netflix, and the wrappers in
webwrap/apps.txt.
The live inventory captured on 2026-10-27 contains no Nuvio, Hayase, NTV or
Sportsurge package. APK files retained on the PC do not mean those apps are installed.

Version 3.9.1 adds wrapper privacy restrictions and verified installs. See
../notes/privacy-maintenance.md. The sections below are historical records of
additions and debugging, not proof that every app is currently installed or safe.
Appstore origin, official releases and self-built wrappers have different trust
boundaries; none by itself proves that an app is free of telemetry.

| App | ASIN | Package (verify after install) | Ad blocking |
|---|---|---|---|
| YouTube | — | `org.smarttube.stable` (SmartTube 32.56) | **Real.** No ad code at all |
| Twitch | — | `com.s0und.s0undtv` (S0undTV beta_146) | **Real.** Playlist proxy (see below) |
| Kick | `B0DNRNVYDQ` | `tv.kick.live` (confirm) | Partial at best |
| Rumble | `B08K9FXY9B` | `com.rumble.battles` | Partial at best |
| frameXTV | — | `tv.framextv.web` (own wrapper) | n/a — website |
| Nuvio | — | `com.nuvio.tv` (native NuvioTV) | n/a — client |

## Why YouTube and Twitch are the genuine wins

**YouTube** serves ads from the same hosts as the video, so a DNS filter has
nothing to block. SmartTube is a reimplementation with no ad code — the ads are
never requested. This is why it works.

**Twitch uses SSAI** (Server-Side Ad Insertion): it stitches the commercial into
the m3u8 playlist on Twitch's own servers before it reaches the device. To the TV
there is no separate ad request — the ad *is* the stream segment. Consequences:

- DNS/blocklist approaches show a purple or black screen, or drop quality.
- Browser workarounds (uBO + TwitchAdSolutions scriptlets) do not exist for TV
  clients, and the main community project was archived in March 2026.

What does work is asking for the playlist from a country where Twitch sells no
ads. S0undTV (beta_144+) has a **Proxy URL** setting for exactly this; only the
playlist request goes through the proxy, the video segments still come straight
from Twitch's CDN, so quality and bandwidth are unchanged. Setup and fallbacks:
see "S0undTV ad-free via Luminous proxy (2026-10-29)" below. Turbo, or a channel
sub (Prime Gaming gives one free sub a month), remain the official routes.

**Kick / Rumble** serve ads from their own CDNs alongside content, so blocking is
partial and frequently breaks playback. Not worth the fragility.

## Do NOT add general ad lists to the on-device filter

`dnsfilter.android` carries a curated **Amazon-only** list. Adding blanket
blocklists would risk these streaming apps, for almost no gain.

## Install flow

```sh
./apps/open-appstore.sh B007SOQBCM
```
Opens the Appstore product page on the TV. Tap **Get** there; Amazon's install
flow cannot be driven from adb (no public API, and simulating keyevents risks
tapping the wrong thing).


## frameXTV + Nuvio (2026-10-25)

| | |
|---|---|
| frameXTV | **web wrapper** — `tv.framextv.web`, 33 KB, built in `webwrap/` |
| Nuvio | **native app** — `com.nuvio.tv` v1.0.0 (versionCode 1062), NuvioMedia/NuvioTV |

### Nuvio is native, not a wrapper

First attempt wrapped `https://nuvio.tv/` and that was wrong twice over: the site is
the **marketing page**, not the client, and an official TV build exists. Now installed
from the official repo instead:

```
repo     NuvioMedia/NuvioTV, release 1.0.0 (2026-09-19)
asset    app-full-armeabi-v7a-release.apk   72,397,315 bytes
sha256   0da412bcd6cb8dd7347d02e979cf3b1120e6fa4fc33d103fc9a76ab711af4b3c
```

**ABI gotcha:** this TV reports `ro.product.cpu.abi=armeabi-v7a` (32-bit only,
`abilist=armeabi-v7a,armeabi`) — the arm64-v8a asset downloads fine and then
fails to install. Always `adb shell getprop ro.product.cpu.abi` first.

Saved as `apps/nuvio-tv-1.0.0-v7a.apk`. Launch activity is
`com.nuvio.tv/.launcher.AppIconDefault`; it ships `LEANBACK_LAUNCHER`, so CleanTV
lists it automatically. Sign-in is a QR code / short code at `nuvio.tv/link`, or
**Continue without account**. No content sources are configured — that stays the
user's call.

### frameXTV stays a wrapper, by necessity

There is no frameXTV APK (any that claims to be one is a repack). A website cannot
be a Fire TV app on its own, so `webwrap/` builds a Leanback WebView shell:
D-pad pointer, OK synthesises the mouse sequence, BACK is web history. Verified on
device: pointer moves with the arrows and a synthetic OK dismissed the welcome
modal and loaded the real catalogue.

## Two more browser shells (2026-10-25)

| Tile | Package | URL | Why a shell |
|---|---|---|---|
| Fights | `tv.obbywatcher.web` | `fight.nswfiles.com` | ObbyWatcher, an HLS fight player — web only |
| MMA Stream | `tv.mmabite.web` | `mmabite.plus` | UFC/MMA stream index — web only |

Neither ships an app and **neither ships a logo**: ObbyWatcher's
`site.webmanifest` declares no `icons` array at all (only `background #08070d`
and a pastel `theme #cdb7ff`), and MMA Stream's only favicon is a third-party
`pngimg.com` UFC PNG. So both tiles are composed from each site's own palette
(Segoe UI Bold, 320x180 banner + 512 icon), not scraped art:

```
Fights      #08070d ground, "Obby" #cdb7ff over "WATCHER" #ebe8f5, "OW" monogram
MMA Stream  #0d0d0f ground, UFC badge left, "MMA" #ebe8f5 / "STREAM" #c62828
```

Verified on device: ObbyWatcher reaches its player (server list, chat panel,
"Reconnecting" state); MMA Stream renders its schedule table (LFC 63, UFC Fight
Night). Both use the same D-pad pointer as frameXTV.

**Build gotcha found here:** `apps.txt` written by Python on Windows picks up
CRLF, and the trailing `
` made `[[ -f icons/x.png ]]` fail on a file that
plainly existed ("icon not found"). `build.sh` now strips `
` from every field,
and `apps.txt`/`home.conf` are written with `newline="
"`.

## frameX tile art = the real logo

`framextv.cc/favicon.svg` is the brand play-mark; the coral square + FRAMEX/TV
wordmark lives on the sibling `framextv.org` (`framextv-logo.webp`, 1100x240 with
alpha). Tile banner is that wordmark scaled into 320x180; the app icon is the
badge cropped from the same file via its alpha bbox. No screenshot crops remain.

### Wrapper v1.2 — D-pad arrows (2026-10-25)

Symptom: the pointer did not move with the remote, though OK clicked. Cause: keys were
handled in `Activity.onKeyDown`, which never sees DPAD arrows because WebView consumes
them for focus navigation; DPAD_CENTER is not consumed, hence the asymmetry. Fix:
override `dispatchKeyEvent`, which runs ahead of the view tree. Proven by logging
`PTR x,y` to logcat: 480,270 -> 612,358 after 3x RIGHT + 2x DOWN, +44 CSS px per press.

All three shells (`tv.framextv.web`, `tv.obbywatcher.web`, `tv.mmabite.web`) are
versionCode 3 / versionName 1.2. `build.sh` now carries `VCODE`/`VNAME` — bump both on
any dex change, and `rm -rf build/dex` if you edit Java, because a cached dex is reused.

### Wrapper v1.5 — media/fullscreen pass (2026-10-25)

Reported: no fullscreen on double tap, video would not play. Root causes were WebView
defaults, not the sites: `requestFullscreen()` needs `onShowCustomView` on the host,
`window.open` players need `onCreateWindow`, http segments need mixed content, and a
synthetic click is not a user gesture so the native fullscreen path stays blocked — hence
the JS pin-the-video fallback bound to a double OK press.

Added: native + fake fullscreen, popup routing, mixed content, autoplay, keep-screen-on
polling, MEDIA_PLAY_PAUSE, MENU toggles fullscreen, BACK exits fullscreen before history.
All three shells are versionCode 6 / versionName 1.5.

### Wrapper v2.0 — native input, the real fix (2026-10-25)

Reported: on frameXTV one click pauses instead of opening the player menu; playback is bad.

Three real defects, all found by instrumenting rather than guessing:

1. **Input was JS-synthetic.** `document.elementFromPoint()` in the top document returned
   `<IFRAME>` — the player lives in a frame — and events dispatched by JS never cross a
   frame boundary. The click never reached the player. Replaced with **native
   `MotionEvent` taps and `ACTION_HOVER_MOVE`**, which the browser routes itself: they
   reach into iframes, fire hover (how a web player reveals its control bar) and count
   as genuine user activation (what `requestFullscreen()` demands). This is TV Bro's
   approach.
2. **`window.devicePixelRatio` lies on this TV.** The panel is 3840x2160 but Fire OS
   overrides the app layer to 1920x1080 at 320 dpi, so Chromium reports dpr **4** while
   the view is 1920 px and the page lays out at 960 CSS px. Every native tap was landing
   at double its intended coordinate. Scale is now derived from `innerWidth`:
   `web.getWidth() / innerWidth` = 2.0, logged as `VIEW 960.0x540.0 scale 2.0`.
3. **My logging drowned itself.** `onConsoleMessage` forwarded every page message, and
   these sites log megabytes of object dumps, rotating the logcat ring buffer and
   discarding the evidence within seconds. Only `PTR/SCROLL/CLICK/HOVER/FULL/MEDIA/TAP`
   markers and `ERROR` level now, which is why the diagnosis worked on the next run.

Result on frameXTV: taps land correctly (`TAP 960,628` welcome, `TAP 168,804` Watch Now),
navigation reaches the player page that was previously unreachable, and a tap inside the
player reveals the site's own play overlay instead of toggling pause.

**Still open, and not fixable from the shell:** once started, the player stays black while
`MediaCodecLogger: HW.video.avc.bitrateInKbps = 251` shows the decoder running. WebView also
logs `Access to text track ... api.framextv.cc/api/subtitles/proxy ... blocked by CORS policy`
and a CORS-blocked default video poster. The player mounts and decodes; the stream itself
supplies no picture. That is the source/CDN layer, not the wrapper.

### Wrapper v2.3 — fullscreen kept the player's controls (2026-10-25)

Reported: "the bottom of the player is cut off in fullscreen mode, but it works, ish".

Measured first, and my layout was innocent: `FULLSCREEN native on view 1920x1080 root
1920x1080 window 1920x1080`, and Fire OS overscan is genuinely off
(`overscan_enabled=0`, `overscan_values=0.0 0.0 0.0 0.0`). Nothing was clipped.

The real cause was *which* fullscreen won. Two mechanisms ran 139 ms apart:

```
FULL on <DIV> box 0,0 960x540 vid 960x540 vp 960x540   <- our pin, controls intact
FULLSCREEN native on view 1920x1080 ...                 <- the site's requestFullscreen
```

`onShowCustomView` hands the browser's raw `<video>` its own surface; the site's custom
control bar is DOM and stays behind. Missing seek bar + buttons at the bottom reads as
"cut off". Fix: the pin now targets the player **container** (an ancestor holding both the
video and a button/control), and while it is active the page's own `requestFullscreen` /
`webkitRequestFullscreen` is replaced with a rejected stub, so native cannot override it.
Unpinning restores the originals.

Back now logs `FULL off <DIV>` then `FULLSCREEN native off` and stays in the app.
All three shells are versionCode 14 / versionName 2.3.

### v2.4 correction — native fullscreen still fires, and that is fine here

Attempts to block the page's own fullscreen while pinned (`requestFullscreen`,
`webkitRequestFullscreen`, then `HTMLVideoElement.webkitEnterFullscreen`) did **not** stop it:
the site evidently holds a reference captured at load time, so re-assigning the prototype
later has no effect. Measured again after each attempt:

```
FULL on <DIV> box 0,0 960x540 vid 960x540 vp 960x540    <- our container pin
FULLSCREEN native on view 1920x1080 ...                 <- site's own fullscreen, still wins
```

But the visual result is correct: ObbyWatcher fullscreens its **player widget**, control bar
included, so the native custom view carries the controls with it. Two screenshots at 1920x1080
show video plus LIVE badge, seek bar, pause, volume, buffer readout and the icon row, with
`FULLSCREEN native on view 1920x1080 root 1920x1080 window 1920x1080` in the log at the same
time. The container pin remains the fallback for players that fullscreen only the bare <video>.

Also corrected an earlier wrong conclusion: `screencap` **does** capture the video here.
The black frames were buffering — frameXTV needed ~60-120 s to reach its first frame, and
`MediaCodecLogger` showed `First Frame Render` + `Resolution change to 1920x800` when it did.

### Wrapper v2.8 — the actual frameXTV fullscreen fix (2026-10-25)

The owner was right that nothing had been fixed on frameXTV, and right that testing on
ObbyWatcher proved nothing (no live stream there). Diagnosis had to come from the device
while frameXTV was playing.

**Root cause: the player is one document down.** frameXTV renders its player in a
same-origin embed iframe:

```
FRAMES 1 | #0 same=true videos=1
src=https://framextv.cc/embed/1290418?autoplay=1&origin=internal
```

`document.querySelector('video')` in the top document therefore returns null (which is what
`FULL no-video (player may be in an iframe)` was reporting), so the container pin had
nothing to grab and `onShowCustomView` took over with the browser's bare media surface. The
site's control bar is DOM in the parent document and stayed behind — the "bottom of the
player is cut off" report was a missing control bar, not clipped geometry
(`FULLSCREEN native on view 1920x1080 root 1920x1080 window 1920x1080`,
`overscan_enabled=0`).

Fixes:
1. `__wwAllDocs()` / `__wwFrameEl()` — enumerate same-origin frames (cross-origin throws and
   is skipped), and map a document back to its `<iframe>` element.
2. `__wwVideo()` searches **every** reachable document, scoring by area with a 4x bonus for
   actually playing, so the embed's video wins.
3. The pin now modifies every element in the chain: the player box and `<html>` inside the
   frame, plus the `<iframe>` element in the parent (`position:fixed; inset:0; 100vw/100vh`).
   All original `cssText` values are saved and restored on un-pin.
4. `onShowCustomView` declines the native surface whenever a video is reachable
   (`FULLSCREEN declined -> container pin (controls kept)`).

Verified on frameXTV with "The Cycle" at 15:54 / 1:52:11 — fullscreen shows the player's own
UI complete: title, seek bar, play/volume, timecode, and the PiP/settings/quality/fullscreen
icon row. Nothing clipped.

**Measured caveat:** while video is actively decoding, `screencap` returns a black frame here
(hardware overlay); the layout is only photographable when paused, and playback has to be
confirmed from `MediaCodecLogger` (`Resolution change ... to 1920x800`,
`bitrateInKbps = 1617 -> 768`). Do not judge content from a black capture.

All three shells: versionCode 19 / versionName 2.8, one shared dex.

### StreamEast + Sportsurge added, Nuvio removed (2026-10-25)

| Tile | Package | URL |
|---|---|---|
| StreamEast | `tv.streameast.web` | `v2.streameast.ga` |
| Sportsurge | `tv.sportsurge.web` | `v2.sportsurge.net/live-sports/` |
| ~~Nuvio~~ | ~~`com.nuvio.tv`~~ | uninstalled; tile removed from `apps.order` |

**Both sites are behind Cloudflare and it does not matter.** From this PC every request
returns `403` with `<title>Just a moment...</title>`, including `/favicon.ico`, so no logo
could be pulled and both tiles are composed art (wordmark + accent rule on #0d1117, Segoe UI
Bold). On the TV the **WebView passes the challenge** and the real catalogues render:

- StreamEast: All/Live/Trending, Premium banner, NFL rows with live scores (Packers 7-7 Lions).
- Sportsurge: search, ALL/FOOTBALL/BASKETBALL/HOCKEY/SOCCER/MOTOR SPORTS, live fixture table
  (`Sporting CP vs Academico de Viseu · LIVE 21' · 8 Streams`).

Logcat does show the challenge plumbing (`hagen.challenges.cloudflare.com` CSP entries) right
before the content appears, so "403 from curl" is not evidence that a shell will fail — check
the device, not the PC. Anyone re-testing these URLs with curl will wrongly conclude they are
dead.

Nuvio's pinned APK (`apps/nuvio-tv-1.0.0-v7a.apk`) is kept for reproducibility but nothing
installs it.

### NTV added, and a per-shell sandbox fix (2026-10-25)

`https://ntv.st/matches/kobra` — and the root `https://ntv.st/` **redirects to that same path**,
so the match URL is effectively the homepage, not a perishable link.

Branding: `og:site_name` NTVSTREAM, `theme-color #ffd700`. Its only icon is a 32x32 favicon
(`/assets/img/icons/favicon-32x32.png`; `/favicon.ico` returns 200 with **0 bytes**), unusable at
tile size, so the tile is type-composed in the real gold on #0b0d10.

**First load failed with a red page:** `Remove sandbox attributes on the iframe tag` plus the
WebView UA — the stream embed refuses to run inside a sandboxed iframe. That iframe lives in the
page we are showing, so the shell can act on the instruction the site itself prints:

- `apps.txt` gained an optional **6th field**. `sandbox` bakes
  `<meta-data android:name="tv.webwrap.stripSandbox" android:value="1">` into that one APK.
- When set, `Main` removes `sandbox` from every `iframe[sandbox]` in the top document and reloads
  once, so the embed re-initialises. Opt-in per shell on purpose: stripping `sandbox` weakens the
  isolation of embedded third-party content, so it is not something to do everywhere by default.

After that the real catalogue loads: LIVE NOW (24), Lions-Packers, Raiders-Rams,
Cardinals-Broncos, US Grand Prix, Barcelona-Real Madrid, and the KOBRA/Channels/Discord/
Favorites/Menu bar.

### Build gotcha that cost two cycles

`if "flags" not in script` is a **false** guard here: build.sh already contains
`force_original_aspect_ratio=decrease:flags=lanczos`, so a substring check for "flags" skipped the
whole patch silently. Also `"$'
'"` inside a Python heredoc becomes a real CR, so anchors
matching that text need raw strings. Assert each anchor instead of guarding on a substring.

All six shells: versionCode 20 / versionName 2.9, one shared dex.

### APK installs: S0undTV (replaces Twitch), Sozo TV, Atlantic (2026-10-25)

| App | Package | Version | Artifact |
|---|---|---|---|
| S0undTV | `com.s0und.s0undtv` | `beta_146` | GitHub `S0und/S0undTV` release, sha256 `8b353200…` ✓ |
| Sozo TV | `com.saikou.sozo_tv` | 1.0.2 | `apisozo.azamov.me` 302 -> `sozo.cdn.azamov.me/.../sozo-tv-1.0.2.apk` (45.2 MB) |
| Atlantic | `st.atlantic.app` | v1.0.6 | `atlantic.st/dl/app/latest.apk`, sha256 `fa896541…` ✓ (from its own manifest.json) |

**Twitch was replaced, not just added.** `tv.twitch.android.viewer` is uninstalled and
`com.s0und.s0undtv` took its slot in `apps.order`. The tile still reads **Twitch**, via the
launcher's display-only rename:

```
name.com.s0und.s0undtv=Twitch
```

Same mechanism as SmartTube -> YouTube: the tile says Twitch, the package and any Settings
entry still say S0undTV. Enabling S0undTV needs a Twitch login (Preferred / LAN / Web tiles).

### S0undTV ad-free via Luminous proxy (2026-10-29)

S0undTV's old built-in ad block stopped working; beta_144 replaced it with three
custom **Proxy URL** slots (changelog bundled in the APK at
`assets/S0undTV_changelog.html`). Configured on the TV:

| S0undTV setting (Settings → Proxy server) | Value |
|---|---|
| Active proxy server | Custom server 1 |
| Custom server 1 | `https://eu.luminous.dev/live/${channel}?allow_source=true&allow_audio_only=true` |
| Custom server 2 | same path on `eu2.luminous.dev` |
| Custom server 3 | same path on `as.luminous.dev` (exits in UZ) |
| Network proxy → Route streams through proxy | OFF (unused) |

`${channel}` is typed literally; the app substitutes it. Do not add `fast_bread=true`
(unsupported). Restart the app after changing proxy settings.

Verified: `curl` against all three returns a master playlist for a live channel (404
just means offline). On the TV, `s0undtv://stream/shroud` played at source (~7.5 Mbps
HW AVC), personalDNSfilter logged `ALLOWED:eu.luminous.dev`, and no ads were seen.
`screencap` shows a black video area while playing — the video layer isn't captured;
use `MediaCodecLogger` lines in logcat to confirm playback instead.

Entering it over ADB (app is not debuggable, so `run-as`/prefs editing is out):
uiautomator dump to find rows, `input tap` the row, then
`input text 'https://eu.luminous.dev/live/\${channel}?allow_source=true&allow_audio_only=true'`
inside a double-quoted `adb shell "…"`, with `MSYS2_ARG_CONV_EXCL='*'` in Git Bash.

If a stream won't start: switch Active proxy server to 2 or 3. If ads come back:
check the public list at github.com/2bc4/streamlink-ttvlol, or self-host
luminous-ttv. Trade-off: the proxy operator sees which channels are watched and
the TV's IP. Never block `luminous.dev`, `s0und.github.io` or
`raw.githubusercontent.com` in the DNS filters (settings and updates load from there).
This setting lives in app data, so `provision/` does not copy it.

### Sozo TV and Atlantic first run (2026-10-25)

Sozo TV opens on `LoginActivity` (needs an account). Atlantic installs, then asks for a
**content plugin** on first run; tapping "Download plugin" pulls and installs it and the app
lands at "Who's watching?".

**Finding the real APK behind an SPA:** never trust the visible page. `atlantic.st/android`
has zero `.apk` references in its HTML; the URL lives in its JS bundle as
`dw="/dl/app/latest.apk"` with a version manifest at `/dl/app/manifest.json` that also
publishes the sha256 and size. Grep the bundled JS, then verify the hash. FlyStream has **no**
reachable APK at all (`/apps` and `/download` contain no `apk` string and no Downloader code;
`/dl/app/latest.apk`, `/app/latest.apk`, `/flystream.apk`, `/api/apps` all 404 or HTML) — its
own meta text says "install it on a Fire TV Stick with Downloader", so it needs the Downloader
code the site/Discord hands out.

### Tile art is a launcher-side override — S0undTV gets the Twitch logo (2026-10-29)

`Catalog.customArt()` reads a PNG **named after the package** out of the launcher's own
external files dir, and it wins over whatever banner the APK ships:

```
/sdcard/Android/data/tv.cleantv.home/files/art/<package>.png
```

So any tile's art can be replaced without touching its APK. That is what the YouTube tile has
been doing all along (`art/org.smarttube.stable.png`), and it is why the S0undTV tile showed
S0undTV's own banner under a label that already read **Twitch**. `apps/art/com.s0und.s0undtv.png`
closes that gap:

```
1280x720, solid #9146FF (Twitch purple), white Glitch mark centred at 50% of frame height,
the mark's two "eyes" knocked back out to #9146FF. Mark only — same convention as the
YouTube tile (solid brand colour + white mark), so the row reads red play mark, purple Glitch.
16:9 because the launcher stretches the file to the card: Tile.onDraw banner.setBounds(0,0,cardW,cardH).
```

**Pushing new art is not enough — the launcher caches art per item.** `Item.artRequested` is set
the first time a tile draws, and `loadApps()` deliberately carries loaded art over to fresh items,
so a running launcher keeps drawing the old banner. Art is only re-read from disk in a fresh
process, and `am force-stop` takes the Guard down with it:

```sh
MSYS_NO_PATHCONV=1 adb push apps/art/com.s0und.s0undtv.png \
  /sdcard/Android/data/tv.cleantv.home/files/art/     # keep MSYS_NO_PATHCONV: Git Bash rewrites the device path
adb shell am force-stop tv.cleantv.home                # also kills the Guard — must be rebound below
adb shell am start -n tv.cleantv.home/.Home            # fresh process, art read from disk
adb shell settings put secure enabled_accessibility_services ''
adb shell settings put secure enabled_accessibility_services tv.cleantv.home/tv.cleantv.home.Guard
```

Once that value is restored the Guard is bound again (`dumpsys accessibility` lists
`Service[label=CleanTV home button]`) and a HOME press lands back on CleanTV — verified by
keyevent 3 with `mResumedActivity: tv.cleantv.home/.Home` afterwards. **Do not stop after the
force-stop**: without the rebind the TV stays on Amazon's launcher.

Verified on device: the APPS strip shows the purple glitch tile, focus label **Twitch**,
next to the red SmartTube/YouTube tile.

### One-command import onto another TV (2026-10-29)

Everything on this TV is captured in `provision/`, so a second TV of the same model is:

```sh
./scripts/capture-tv.sh   <working-tv-ip>    # TV -> repo, read-only on the TV
./scripts/provision-tv.sh <new-tv-ip>        # repo -> new TV, then it verifies
```

`provision/README.md` has the coverage table and the caveats. What mattered here:

- **The device is the source of truth, and the repo had already drifted.** `apps/home.conf`
  was two keys behind the TV: `apps.order` had been reordered on the TV (Sozo first, Atlantic
  in the list, Luna/Prime Video moved to the end) and `apps.hide` had grown
  `com.amazon.spiderpork` + `com.amazon.firebat` — both captured now. The launcher rewrites
  its own copy and drops every comment but its header, so capture **merges values into the
  repo file** (`scripts/home_conf.py diff|merge`) rather than copying it; a byte comparison
  reports a difference on every single run.
- **APKs that existed only on the TV.** Kick 1.9.0, Rumble 2.11.0, X 1.3, SmartTube 32.56 and
  dnsfilter 1.50.61.3 were not in the repo. `pm path` + `adb pull` retrieves them byte-exact —
  the "adb pull is denied for /data/app" note above applies to `/system/priv-app`, not to
  third-party packages. They now live in `provision/apk/` (~80 MB; SmartTube is 35 MB of it,
  and it is re-fetchable from the pinned URL in `cleantv/scripts/youtube.sh`).
- **Wrapper APKs were referenced from a build output** (`apps/webwrap/out/`, git-ignored), so
  capture keeps its own copy in `provision/apk/` for anything it finds there: a golden state
  must not depend on an artefact a clean checkout would not have.
- **`cleantv/scripts/launcher.sh` would have installed upstream CleanTV, not CleanTV** —
  `launcher/install.sh` downloads the GitHub release and checks it against
  `launcher/version.env`. Staging our APK at `launcher/build/cleantv-home-1.3.apk` and pointing
  `version.env` at it (`VERSION_CODE=5`, `APK_SHA256=87fbd89d…`) makes the HOME takeover
  install the CleanTV build offline, still checksum-verified.
- **The launcher signing key is gone.** `apps/cleantv-home.apk` is signed `CN=CleanTV`
  (`8E:11:E2:CE…`); there is no keystore anywhere under `firetv/`, `%USERPROFILE%\.android`
  holds only the stock debug key, and `.gitignore` excludes `*.keystore`. Importing the
  existing APK is unaffected; rebuilding it is — see private/README.md. (Superseded the same
  day: the launcher was renamed to its own application id with a fresh key, below.)

Verified on device: `./scripts/provision-tv.sh <tv-ip> --verify-only` passes against the
source TV — 15 packages by versionCode and pulled-APK sha256, `home.conf` by key/value, both
art files by bytes, the 39-package disabled list, the VPN/alarm/accessibility settings, and a
real HOME press landing back on CleanTV.

### Renamed: dumbtv -> CleanTV everywhere (2026-10-29)

The launcher's *label* has been CleanTV since 2026-10-25, but everything around it still said
dumbtv: the folder, the config file, the script paths and — the one that mattered — the
application id `tv.dumbtv.home`. All of it is renamed.

| was | now |
|---|---|
| `dumbtv/` | `cleantv/` |
| `dumbtv/dumbtv.conf` | `cleantv/cleantv.conf` |
| `build/dumbtv-home-<v>.apk` | `build/cleantv-home-<v>.apk` |
| `tv.dumbtv.home` (app id, Guard entry, accessibility service, `/sdcard/Android/data/...`) | `tv.cleantv.home` |
| versionCode 5 / versionName 1.3 | versionCode 6 / versionName 1.4 |

What to know:

- **This was a migration, not a rename in place.** A new application id is a different app to
  Android, so the order was: install the new one alongside (`cleantv/launcher/install.sh`,
  which now also strips the *old* package's Guard entry, so two launchers cannot fight over
  HOME), push `home.conf` + tile art + wallpaper to
  `/sdcard/Android/data/tv.cleantv.home/files/`, force-stop and restart so the per-tile art
  cache is re-read, rebind the Guard, then `adb uninstall tv.dumbtv.home`. HOME landed on
  CleanTV both before and after the uninstall — verified with keyevent 3 and `mResumedActivity`.
- **A new signing key came with it**, because the old one is unrecoverable and the id was
  changing anyway: `scripts/build-launcher.sh` creates `private/cleantv.keystore`
  (`CN=CleanTV`, `40:DB:8E:0A:…`), builds, signs and verifies in one run, and updates
  `APK_SHA256` in `cleantv/launcher/version.env`. The old APK is kept for rollback only
  (`provision/apk/legacy-launcher-v1.3-code5-tv.dumbtv.home.apk`); provisioning never installs
  it, since a rollback also restores the old app id.
- **The installer no longer downloads anything.** `launcher/install.sh` used to fetch
  upstream's release APK when the staged file was missing or its hash differed — that file is
  the *old* application id, so it would have installed a foreign package and left the HOME hook
  pointing at nothing. It now stops with instructions (build, or stage via `capture-tv.sh`).
- **Upstream links are deliberately untouched**: `dumbtv.org`, the GitHub badges and the git
  remote (renamed `origin` -> `upstream`) still point at the original project. The fork banner
  at the top of cleantv/README.md says so.
- Not renamed: `backups/` (dated snapshots of what the device looked like at the time) and the
  `dumbtv-blocklist.txt` file already on the TV — `cleantv/scripts/dnsfilter.sh` pushes the new
  name on its next run, and the old file is simply orphaned until then.

**Verification note.** The fork's own pytest suite cannot run on this machine: its fake adb is
invoked through `#!/usr/bin/env python3`, and `python3` here is the Microsoft Store stub, so
`calls.jsonl` is never written (84 failures that say nothing about the code — pre-existing). The
rename was verified by building the APK (javac `-Werror` clean, `aapt2 dump badging` shows
`tv.cleantv.home` / versionCode 6 / label CleanTV), `apksigner verify`, and the device checks
above.

### Wrapper v3.8 — cross-origin frame-pin fullscreen (2026-10-25)

Reported: "in fullscreen the whole thing is visible. NOTHING has changed." — StreamEast
fullscreen did nothing while the chat bar kept eating the view. The v3.6 chat-hide worked
windowed (`CHAT hidden 1`), but fullscreen used **contain-zoom on the page**, which is a
measured no-op when the player iframe already spans the viewport width:
`FULL zoom x1.00 frame 960x335` — `Math.min(960/960, 540/335)` caps at 1.0.

Fix: `__wwFrameFull` now **pins the frame element** instead of scaling the page. The
`<iframe>` lives in the host document even when its contents are cross-origin, so it is fixed
to `100vw/100vh` directly and every sibling up the ancestor chain is hidden (cssText saved,
restored on toggle-off). The inner player relayouts into the full screen and keeps its own
controls. `__wwBestFrame` now never picks a chat frame as "the player" — the stacked twitch
chat embed is *bigger* than the video frame, and pinning it would fullscreen the chat.

Verified on device, StreamEast on a live game:

```
CHAT hidden 1
FULL frame-pin 960x335 -> 960x540     <- pin fills the viewport
MediaCodecLogger: HW.video.avc ... bitrateInKbps = 4904 -> 2900   <- real stream decoding
FULL off                                <- MENU toggles back
FULL frame-pin ... / FULL off            <- BACK exits fullscreen first, correct order
```

frameX re-verified same-origin: `FULL on <DIV> in-frame box 0,0 960x540 vid 960x540` with
Clayface decoding at 8.2 Mbps. Fights pins its player widget (`FULL on <DIV> top 960x540`).
MMA Stream: clean launch, correct `FULL no-video and no frame` with no content (its 2016
LFC 63 card has no VOD — site-side). All four shells: versionCode 29 / versionName 3.8,
one shared dex.

**The v3.7 build never worked, and how that was caught.** v3.7 shipped a missing `+` in a
Java string concat — the page-side JS died with `Uncaught SyntaxError: Unexpected token '>'`
and the *entire* EXTRAS payload (chat hide, frame-pin, sandbox strip) silently went missing;
on the TV the only symptom was `FULL no-video and no frame` and no `CHAT hidden`. Two
defences now exist: `tools/check-js.js` extracts the EXTRAS/POINTER payloads from
`Main.java` and syntax-checks them with node inside `build.sh` **before** the dex is baked
(it caught a second missing operator during the v3.8 build), and the console filter surfaces
injection-time SyntaxErrors as logcat lines, so a dead payload is visible from `adb logcat
-s webwrap` next to the injection point rather than three symptoms downstream.

**Blind-testing a TV WebView from ADB:** `adb shell input tap X Y` lands real touches at
exact device coordinates, and Windows OCR (WinRT `Windows.Media.Ocr`) reads a pulled
`screencap` including per-word bounding boxes — tap targets for "Watch Now", match cards
and stream tabs can be located without a human at the screen. The webwrap logs
(`TAP`, `VIEW`, `FRAMES`, `FULL`, `CHAT`) plus `MediaCodecLogger` remain the playback oracle:
a ~10 KB black `screencap` while `HW.video.avc` shows a bitrate means video is decoding, not
that the screen is broken.

### APK installs: Aerial Views, X-plore (2026-10-29)

| App | Package | Version | Artifact |
|---|---|---|---|
| Aerial Views | `com.neilturner.aerialviews` | 1.8.5 (148) | GitHub `theothernt/AerialViews` release `aerial-views-1.8.5.apk`, sha256 `a20b4bc7…` = GitHub asset digest ✓; signer CN=Neil Turner, cert sha256 `383b3b2d…` |
| X-plore | `com.lonelycatgames.Xplore` | 4.46.00 (44600) | lonelycatgames.com/apps/xplore direct download (no published checksum), sha256 `1f019bde…`; signer O=Lonely Cat Games, cert sha256 `d46cd5fa…` |

Both carry `armeabi-v7a` code and a leanback launcher activity; min SDK 23 / 26, so fine
on SDK 28. Tiles sit after X in `apps.order`, default labels. X-plore is closed source
and wants INTERNET (for its LAN/cloud browsers) — it's a file manager, keep it off
anything sensitive. Update it from the same page; it is also on the Appstore
(`B00LLG7AR8`) if store updates are preferred.

**Aerial Views is the screensaver.** Originals saved in
`backups/screensaver-2026-10-29_195030/settings-before.txt` (Amazon's
`com.amazon.ftv.screensaver/.app.services.ScreensaverService`, enabled, 5 min timeout).
Applied, per the Aerial Views README for Fire OS 7:

```sh
C=com.neilturner.aerialviews/.ui.screensaver.DreamActivity
adb shell settings put secure screensaver_components $C
adb shell settings put secure screensaver_default_component $C
adb shell settings put secure screensaver_enabled 1
adb shell appops set com.neilturner.aerialviews SYSTEM_ALERT_WINDOW allow   # frame-rate switching
```

Revert: put the Amazon component back into the first two keys. The adb shell cannot
start a dream to test it (`service call dreams 1` → missing `WRITE_DREAM_STATE`), so
proof is waiting out the 5-minute idle or using the preview inside the Aerial Views app.
These are secure settings, not app data: `provision/` does not re-apply them.

### APK installs: ARVIO, CloudStream, Lumera, Watchbox, Zangetsu (2026-10-29)

Picked from a GitHub sweep (Awesome-Android-TV-FOSS-Apps + topic pages) for "more
like Sozo/Atlantic". Every APK is the repo's own GitHub release asset, sha256 equal to
the digest GitHub publishes for it, and each was checked on the PC with `aapt2 dump
badging` for min SDK <= 28 and an `armeabi-v7a` build before install.

| Tile | Package | Version | APK in apps/ | Signer | Notes |
|---|---|---|---|---|---|
| ARVIO | `com.arvio.tv` | 2.3 (321) | `arvio-2.3.apk` (`ARVIO-v2.3-sideload-release.apk`) | CN=ARVIO, NL | media hub, leanback; 139 MB |
| CloudStream | `com.lagradost.cloudstream3` | 4.8.0 (68) | `cloudstream-4.8.0.apk` | CN=LagradOst | stable, not the rolling pre-release; ships no providers — add repos in-app |
| Lumera | `com.lumera.app` | 0.1.8-beta (9) | `lumera-0.1.8-beta.apk` | CN=notadough | Stremio addons via Settings → Addons (no URL scheme); repo idle since 2026-04 |
| Watchbox | `space.nicart.watchbox.tv` | 4.14.12-tv (91) | `watchbox-tv-4.14.12-v7a.apk` | O=Nicartjay | real TV build; tiny repo (6 stars) |
| Zangetsu | `com.spyou.watch_app` | 2.3.4 (22630) | `zangetsu-2.3.4-v7a.apk` | O=Spyou | `-tv.apk` asset is byte-identical to `-universal`, so the 63 MB v7a split was used; leanback launcher present |

Tiles sit after Atlantic in `apps.order`, default labels. First launch not yet tested on
the TV (it was in use). Rejected in the sweep: Streamflix Reborn (repo 404), Anikku and
Flixclusive (no leanback launcher activity, phone UI). NuvioTV 1.1.0-beta.8 also passes
the checks if it's wanted back. All of these pull from third-party sources; same
trust/legal footing as Sozo and Atlantic.
