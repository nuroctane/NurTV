# apps — TCL_65Q650F

## App label: CleanTV — renamed everywhere 2026-10-29

The label lives in one resource: `cleantv/launcher/res/values/strings.xml` (`app_name`).
The folder, the config file, the script paths and the application id were renamed too —
see apps/manifest.md, "Renamed: dumbtv -> CleanTV everywhere".

Build with the repeatable script (it finds the SDK, build-tools and JDK, signs with
`private/cleantv.keystore`, verifies the signature, and updates `APK_SHA256` in
`cleantv/launcher/version.env`):

```
./scripts/build-launcher.sh
```

Output: `cleantv/launcher/build/cleantv-home-<VERSION>.apk` (what
`cleantv/launcher/install.sh` installs) and `apps/cleantv-home.apk` (the repo's copy).
Current build: `tv.cleantv.home` v1.4, versionCode 6, sha256 `eb7d364b…`.

Upstream's own `launcher/build.sh` cannot run here: it wants `platforms/android-25` (this
SDK has `android-35`), it calls `zip` which Git Bash lacks, and it compiles with `-Werror`,
which fails on the deprecation warnings a newer `android.jar` produces.
`scripts/build-launcher.sh` is that recipe made repeatable — including the two things that
cost time: file lists for `javac`/`d8` must carry Windows paths, and the SDK tools are
`.exe`/`.bat` that need Windows-style arguments.

### Gotchas that cost time

- **`MSYS_NO_PATHCONV=1` breaks Windows .exe/.bat.** It stops bash converting
  `/c/...` to `C:/...`, so `aapt2.exe` and `apksigner.bat` receive POSIX paths
  they cannot open and return *empty* output rather than an error. Use Windows
  paths for those tools; keep `MSYS_NO_PATHCONV=1` only for `adb shell` device paths.
- **`.bat` wrappers need a Windows-style `JAVA_HOME`** (`C:\Program Files\...`).
  The POSIX form fails with "Please set the JAVA_HOME variable".
- **New signature ⇒ cannot upgrade in place.** `adb uninstall` first, then install.
  Uninstalling deletes `/sdcard/Android/data/tv.cleantv.home/files/`, so back up
  `home.conf` + `wallpaper.jpg` first and restore after.
- **`am force-stop tv.cleantv.home` kills the Guard**, so HOME reverts to Amazon's
  launcher. Rebind by setting `enabled_accessibility_services` to empty, then back
  to `tv.cleantv.home/tv.cleantv.home.Guard`. No reboot needed.

## Installed

| Package | Source | Notes |
|---|---|---|
| `org.smarttube.stable` | SmartTube GitHub, checksum-pinned | ad-free YouTube |
| `tv.twitch.android.viewer` | Amazon Appstore | note: **.viewer**, not .app |
| `com.kick.mobile` | Amazon Appstore | |
| `com.rumble.firetv` | Amazon Appstore | |
| `com.x.xtv` | Amazon Appstore (03:07) | **X (Twitter) TV — installed by owner on purpose, keep** |
| `tv.cleantv.home` | built here | label **CleanTV** |
| `dnsfilter.android` | CleanTV | always-on VPN |

## Wallpapers

`apps/wallpapers/*.jpg` — 1920x1080 frames pulled from the Wallpaper Engine
*video* projects (the launcher cannot animate; these are stills).

- `dark-waves.jpg` — applied (silver moonlight on black water)
- `dark-clouds.jpg`, `sea-waves.jpg` — alternates
- `blackhole.jpg` — too bright, washes out tile labels

## Amazon codename map (verified 2026-10-25)

The launcher tile labels do **not** match package names, and APK labels are
unreadable here — `adb pull` is denied for `/system/priv-app` **and** `/data/app`
on this Fire TV. Identified by walking the APPS row with D-pad RIGHT/OK and
reading `mResumedActivity` after each launch, then confirming with a screenshot.

| Tile label | Package | Notes |
|---|---|---|
| Luna | `com.amazon.spiderpork` | confirmed: "Who's playing on Luna?" |
| Prime Video | `com.amazon.firebat` | confirmed: "Who's watching Prime Video?" |
| Amazon Music | `com.amazon.bueller.music` | |
| Netflix | `com.netflix.ninja` | |
| X | `com.x.xtv` | owner-installed, keep |
| Appstore | `com.amazon.venezia` | `.grid.AppsGridLauncherActivity` |
| SmartTube | `org.smarttube.stable` | |
| Twitch | `tv.twitch.android.viewer` | |
| Kick | `com.kick.mobile` | |
| Rumble | `com.rumble.firetv` | |

**Dead ends** (don't repeat): `com.amazon.gamehub` is *not* Luna, `com.amazon.vizzini`
is *not* Prime Video, and `dumpsys package` on Fire OS 7 contains **zero**
`LEANBACK_LAUNCHER` strings, so it cannot be used to enumerate tiles.

## Removed / hidden (2026-10-25)

- **Luna** — `pm uninstall --user 0 com.amazon.spiderpork`. Fire OS reverts an
  updated system app to its preinstalled stub rather than deleting it: the package
  remains listed as `versionName=1.0-stub-release`. NOTE: `enabled=0` in the User 0
  line is COMPONENT_ENABLED_STATE_**DEFAULT**, i.e. *enabled* — not disabled. The
  tile disappears because the remaining stub declares no Leanback launcher
  activity, not because the package was disabled.
  Restore: `cmd package install-existing com.amazon.spiderpork`.
- **Amazon Music, Netflix, Prime Video** — hidden from the home screen only via
  `apps.hide` in `home.conf`. All three still installed and working; reachable by
  voice search or Amazon's own launcher (hold HOME).


## TV inputs (verified 2026-10-25 via `dumpsys tv_input`)

The hardware connection map is authoritative — `hdmi_port` proves which tile is
which physical socket.

| Input id | Hardware | Tile |
|---|---|---|
| `com.droidlogic.tvinput/.services.Hdmi1InputService/HW5` | `hdmi_port=1` | **PlayStation 5** (renamed) |
| `.../Hdmi2InputService/HW6` | `hdmi_port=2` | HDMI2 |
| `.../Hdmi3InputService/HW7` | `hdmi_port=3` | HDMI3 |
| `.../AV1InputService/HW1` | type=3 (composite) | Composite |
| `.../ADTVInputService/HW16` | type=2 (tuner) | (not shown) |
| `.../Hdmi1InputService/HDMI100004` | **no hardware connection** | hidden (duplicate) |

`Hdmi1InputService` registers twice: `HW5` is the real HDMI1 socket, `HDMI100004`
is a virtual CEC entry with no `Connection{}` block. Keep one and hide the other:

```ini
inputs.hide=com.droidlogic.tvinput/.services.Hdmi1InputService/HDMI100004
name.com.droidlogic.tvinput/.services.Hdmi1InputService/HW5=PlayStation 5
```

To name a different port, read its `hdmi_port` from `dumpsys tv_input` first —
never guess by service name.

## AirPlay tile: permanently dead on CleanTV

`com.apple.airplay.amazon.airplay/.MainActivity` is gated behind a **signature-level
Amazon permission**:

```
Permission Denial: starting Intent { cmp=com.apple.airplay.amazon.airplay/.MainActivity }
requires com.amazon.airplay.permission.LAUNCH
```

A third-party launcher can never hold that permission, so the tile always bounces
back to the home screen. Not a config problem and not fixable. AirPlay *reception*
is a system service — cast from the iPhone and it works without that tile.
Hide it if it is just decoration:
`apps.hide=...,com.apple.airplay.amazon.airplay`
