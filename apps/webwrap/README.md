# webwrap — a website as a Fire TV app

A site with no APK still needs one to appear on CleanTV: the launcher only lists
apps with a `LEANBACK_LAUNCHER` intent filter. This builds that shell — one small
WebView activity, no libraries, no Gradle, network access to the site and any third-party resources it loads.

Only apps that genuinely have no TV build belong here. Nuvio was wrapped first and
then correctly replaced by its official `NuvioMedia/NuvioTV` APK.

## Version 3.9.1 hardening

Builds always recompile DEX and require Node syntax/behavior checks and Java
navigation-policy tests. out/<slug>-tv.json records the source and APK hashes.
The installer backs up old APKs and verifies installed bytes:

    python scripts/update-wrappers.py --serial <tv-ip>:5555

Run that from the project root. Builds use the original signing key at
~/.local/share/firetv-keys/webwrap.keystore (override WEBWRAP_KEYSTORE). Keep the
same key for updates; no new key is generated automatically. WEBWRAP_KEYPASS
supplies its local password. Signing material is excluded from project artifacts.

Third-party cookies and HTTP media are off by default; top-level navigation and
popups use exact approved HTTPS hosts. No current app permits sandbox stripping.
Only StreamEast enables the chat-hide timer. Hold MENU for Reload/Clear site data;
tap MENU for fullscreen. Logs are opt-in and omit raw page errors and URLs.

See ../../notes/privacy-maintenance.md for policy flags, exception handling,
privacy limits and the required playback checks. The remaining sections record
historical debugging; the current code and policy take precedence.

## Build

```sh
./build.sh            # every app in apps.txt
./build.sh framextv   # one
```

Output: `out/<slug>-tv.apk`, signed with the external original key
(passphrase `webwrap`). **Keep the keystore** — updates must be signed with it or
they cannot install over the old one.

Needs a JDK 17+ (`Program Files/Eclipse Adoptium`), Android SDK `platforms;android-35`
and any `build-tools` (default 35.0.0), plus `ffmpeg` on PATH for banner generation.

## Adding a site

1. `cp something.png icons/<slug>.png` (512x512 is ideal)
2. one line in `apps.txt`: `slug|applicationId|Label|https://url/|icons/<slug>.png`
3. `./build.sh <slug>` and `adb install -r out/<slug>-tv.apk`

`icons/<slug>-banner.png` (320x180) overrides the generated banner, which is the
icon centred on the site's dark background colour.

Nothing else is needed: the activity ships `LEANBACK_LAUNCHER`, so CleanTV's
`Catalog.apps()` picks it up (`shown()` lists every leanback app) without touching
`apps.show`. Add it to `apps.order` in `home.conf` only to control position.

Icon art note: `framextv.cc/icon-512.png` is a plain pink square, **not** the
brand mark. The real `fX` badge only exists rendered in the site's welcome modal,
so `icons/framextv.png` is a crop of that modal from a device screenshot.

## How a remote drives a website

A Fire TV remote emits no touch events. Fixing that is the whole point of
`src/tv/webwrap/Main.java`:

| Key | Effect |
|---|---|
| D-pad arrows | move an injected pointer 44 px |
| OK / Enter | synthetic `mouseover → mouseenter → mousemove → mousedown → mouseup → click` at the pointer |
| BACK | `WebView.goBack()`, then leaves the app |
| Page up/down, prev/next | scroll 600 px |

### Why keys are read in `dispatchKeyEvent`, not `onKeyDown`

The first build (v1) used `Activity.onKeyDown` and **the pointer never moved with the
remote's arrows**. `onKeyDown` only runs for keys the focused view did *not* consume,
and WebView eats DPAD arrows for its own focus navigation. DPAD_CENTER is not eaten,
which is why OK already worked while arrows did nothing — and why my earlier device
check passed: I had only verified the click, not the movement.

`Activity.dispatchKeyEvent` runs before the view hierarchy, so overriding it takes
every key first. The `UP` of a handled key is swallowed too, so WebView never acts on it.

Verified with instrumentation rather than eyeballing: the page logs `PTR x,y` on every
move and `CLICK x,y` on every press, surfaced through `WebChromeClient.onConsoleMessage`:

```sh
adb logcat -s webwrap | sed -n '/PTR\|CLICK/p'
# PTR-READY 480,270   -> start = centre of the 960x540 CSS viewport (2x device pixels)
# PTR 612,358         -> after 3x RIGHT, 2x DOWN (+44 each)
```

Holding an arrow accelerates (step grows to 66 on key repeat). The step is in CSS
pixels, so on this TV 44 CSS px = 88 device px.

The click climbs up to 4 ancestors looking for `A`, `BUTTON`, `[role=button]`,
an `onclick`, or `cursor:pointer`, because card art is rarely the click target.
Pointer state lives in the page, so it survives SPA route changes.

## Media: what a TV browser must do that a bare WebView does not

Researched against TV Bro (GPL-3 — studied, not copied) and the WebView docs, after a
report that video would not play and would not fullscreen.

| Problem | Why | Fix |
|---|---|---|
| Page's fullscreen button does nothing | `requestFullscreen()` is ignored unless the host implements the callback | `WebChromeClient.onShowCustomView/onHideCustomView` swap the video view in as a fullscreen child |
| Clicking play does nothing | players open in `window.open` / `target=_blank`; multi-window off makes it a no-op | `setSupportMultipleWindows(true)` + `onCreateWindow` routes the popup URL back into the main WebView |
| Video request blocked | stream segments are often plain `http` inside an `https` page | `MIXED_CONTENT_ALWAYS_ALLOW` |
| Autoplay refused | Chrome requires a gesture | `setMediaPlaybackRequiresUserGesture(false)` (TV Bro's `allowAutoplayMedia`) |
| Double tap does nothing | a synthetic click is **not** a user gesture, so the native path stays blocked | JS fallback pins the largest/live `<video>` to `100vw/100vh`, and **OK twice** (420 ms) toggles it; `MENU` does it too |
| Player is cross-origin, no `<video>` reachable | `contentDocument` throws; native fullscreen hides the WebView that was drawing the player (black + spinner); contain-zoom is a no-op when the frame already spans the width (measured `FULL zoom x1.00`) | pin the player **iframe element** itself to `100vw/100vh` and hide every sibling up the ancestor chain (StreamEast: `FULL frame-pin 960x335 -> 960x540`); chat embeds (`twitch.tv/embed`, `/chat`) are never picked as the player frame |
| Screen sleeps mid-film | — | a 2 s poll of `<video>.paused/readyState` drives `FLAG_KEEP_SCREEN_ON`, so it only stays on while something plays |
| No play/pause key | — | `MEDIA_PLAY_PAUSE` -> `<video>.play()/.pause()` |

Verified on device (ObbyWatcher, which has a real `<video>`):

```
CLICK 480,270 <VIDEO>
CLICK 480,270 <VIDEO>
FULL on <VIDEO>
```

Two synthetic clicks inside the double-press window, then the video pinned to the
viewport — confirmed by screenshot, not just by the log.

**What this does not fix:** a source that returns an HTML error page or a 403. Fullscreen
and popup routing are player plumbing; they cannot turn an error page into video. Check
the log for a decoder/HTTP error to tell the two apart.

## Gotchas that cost time here

- **`apksigner.bat` has no exec bit** after `sdkmanager` unzips it, so an `-x` probe
  silently falls through to a bare `apksigner` that does not exist. The script uses
  `-f` and runs `java -jar build-tools/*/lib/apksigner.jar` instead — which also
  removes the Windows-style-`JAVA_HOME` requirement.
- **`zip` does not exist in Git Bash**; `python`'s `zipfile` adds the shared
  `classes.dex` to the APK instead.
- Windows paths for `aapt2.exe`/`zipalign.exe`, POSIX paths for `javac`. Keep
  `MSYS_NO_PATHCONV=1` for `adb shell` device paths only.
- One dex is compiled once and shared by every app; each APK differs only by
  manifest, icon and banner.
