# Building the patched Lumora (MMA + motorsports)

## The patch

`mma-motorsports-events-2026-11-07.patch` — 45 files, +2114/-63, against
pristine Lumora v7.1 (`c0be28d`, `versionCode 71`). Verified to apply
cleanly to a pristine `c0be28d` checkout (`git apply --check`, 2026-11-07).

What it adds: MMA as a fixture-feed sport (API-Sports `/fights` on host
`v1.mma.api-sports.io`) and Formula 1 as a fixture-feed sport (`/races`),
plus MotoGP, NASCAR, IndyCar, WEC, WRC and Formula E as guide-only sports
with their own chips, icons and keywords. Event rows hide the score boxes
for fights/races. Plus a built-in IRC client for the ModdingCartel fight
chat (irc.obnoxious.lol:6697 TLS, channel configurable, nick default
`nuroctane`) and the behind-live-window player recovery from the Media3
demo app. Build 7 adds two more fixes: `StreamContentSniffer` probes
extensionless URLs (Samsung TV Plus `jmp2.uk/stvp-*` HLS) and the EPG
`FeedChannelResolver` with ranked matching plus `ufc.us`/`ufc.uk`
exclusion. See the patch's CHANGELOG entry for the full list.

## Apply and build

```sh
git clone https://github.com/LumoraPlayer/Lumora lumora
cd lumora
git checkout c0be28d
git apply /path/to/mma-motorsports-events-2026-11-07.patch
./gradlew :app:assembleRelease
# output: app/build/outputs/apk/release/app-release.apk
```

Run the unit tests before shipping a build:
`./gradlew :app:testDebugUnitTest` (the patch adds/updates sports tests).
Build 7 skipped the test gate per his order on that job — release APK
only, no separate test run.

## Key slots (build-time, never committed)

Sports fixture keys are **build-time** (`BuildConfig.API_SPORTS_KEYS` /
`SPORTAPI_KEYS`, fed from `keystore.properties` or CI env) — not per-device
secrets. A build with no keys still compiles and runs; the board just falls
back to guide-only for every sport.

`keystore.properties` at the repo root (gitignored, never committed):

```properties
# Release signing (required for an upgrade-in-place over the installed
# stock 7.1 — a different key cannot upgrade it, only replace it via
# uninstall/reinstall; the stock release key is upstream's, so a local
# build signed with a new key REPLACES the install and wipes its data
# unless the same key is used)
storeFile=/path/to/keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
# API-Sports keys, comma-separated, tried in order. Qualify per sport when
# the plan behind the key does not cover that product:
#   apiSportsKeys=mma:<mma-key>,formula-1:<f1-key>
# or a bare key if the plan covers all products. Without mma:/formula-1:
# entries the MMA/F1 boards stay guide-only.
apiSportsKeys=
# Trakt OAuth app (optional; blank = Trakt pane reports unconfigured)
traktClientId=
traktClientSecret=
# SportAPI.ai keys, comma-separated (football only, optional)
sportApiKeys=
```

Environment equivalents (CI): `API_SPORTS_KEYS`, `TRAKT_CLIENT_ID`,
`TRAKT_CLIENT_SECRET`, `SPORTAPI_KEYS`. Free API-Sports tier is ~100
requests/day per sport. API-Sports products needed: MMA
(`v1.mma.api-sports.io`) and Formula 1 (`/races`).

## Build result (2026-11-07, his PC)

Built on the PC with JDK 17 and the Android SDK (platforms 35/36,
build-tools 36.0.0). Build 6 went green on release and tests
(2026-11-07 13:48–14:00 CT): `TESTS_EXIT=0`, `BUILD_EXIT=0`, confirming the
`!!` fix for the `IrcMessageTest` nullability compile failure from the
earlier build. APK `C:\Users\david\Scripts\lumora-work\lumora-patched-7.1.apk`
(39,952,686 bytes), sha256
`af21e4ffbc92effeebc3f8590904c40f6af7b6d96c8659653a3aff956bde4507`,
package `com.lumora`, versionCode 71001, versionName 7.1. Installed on the
TV 2026-11-07 14:05:50 CT via `adb install -r` — an in-place upgrade over
the earlier patched build, same signing key, data preserved
(`firstInstallTime` still 2026-11-07 13:15:21). Build 5 was the first
patched build, installed as a fresh install (stock uninstalled first).

Release signing key: `C:\Users\david\Scripts\lumora-work\lumora-release.jks`
(RSA 2048, alias `lumora`, generated 2026-11-07), password only in
`C:\Users\david\Scripts\lumora-work\lumora-keystore.properties`. Reuse it for later
patched builds so they upgrade this one in place. The release is
debuggable on purpose so the app private data can be provisioned with
`adb shell run-as`.

Build 7 went green on the second assemble (2026-11-07 ~16:30–17:00 CT,
Grok Build on the VM driving the PC build): `BUILD_EXIT=0` in 5m 3s.
The first assemble failed in 2m 32s on three compile errors in the new
EPG resolver (`XmltvChannel` unqualified — it only exists as
`XmltvParser.XmltvChannel`); the two signatures were qualified, the
patch regenerated (45 files, sha256
`8845ef9a3fe45efd0ab29233b6df4b43cb8a1fcd26ac4138fae8c57660c09b62`),
rebuilt once, green. APK
`C:\Users\david\Scripts\lumora-work\lumora-patched-7.1.apk`
(39,954,802 bytes), sha256
`84229b1812f2447a54d98b5a0ff47d2da60013848a0c9e52c1493583380d32b6`,
package `com.lumora`, versionCode 71001, versionName 7.1. Installed on
the TV 2026-11-07 ~17:00 CT via `adb install -r` — an in-place upgrade
over build 6, same signing key, data preserved. Playback verified live
after install: Samsung NASCAR, Pluto NFL Channel, NHL Network, beIN
Sports USA and beIN XTRA all play; UFC HLS plays in fullscreen once the
relay went live; zero parse errors in logcat. Favorites expanded to 92
URLs; UFC guide re-synced clean under the new resolver.

## Install the built APK

```sh
adb connect <tv-ip>:5555
adb install -r app-release.apk
```

Uninstall first only for the very first patched build: a locally built APK
signed with a new key cannot upgrade the stock install in place, so the
first patched build is a fresh install and the app private data is wiped.
Provision afterwards from `provision/lumora/README.md` again (plugins/add-ons
live in the app private data dir, which an uninstall wipes). Later builds
signed with the same local key upgrade in place with `install -r`.

## Household 7.5 build (one APK with everything)

Since 2026-11-21 the TV runs a single household APK built from Lumora 7.5
(`provision/custom-lumora75`, gitignored, upstream `268a9d2` plus the
MMA/motorsports patch). It installs as `com.lumora.debug` next to the official
`com.lumora`, because the official app is signed with upstream's key and no
local build can replace it in place without wiping its data. The launcher's
"Sports" tile points at the household build; the official app stays installed,
hidden, as a fallback.

What the APK carries (private, never committed):

- `app/src/main/assets/household-seed.json`: a Lumora backup document with the
  16 providers (Sports Fallback, Rebel Live, UFC and the rest) and the 101
  favourites, including both UFC streams.
- `app/src/main/assets/household-plugins/*.js`: the four plugins from
  `provision/lumora/plugins/`.

On first launch `HouseholdSeed.kt` applies the seed through the app's own
restore path, installs and enables the plugins, and only then sets
`household_seed_v1`. A partial seed retries on the next launch.

Build: `gradlew.bat :app:assembleDebug --max-workers=4 --no-parallel` (through
`lowcpu.ps1`), then copy `app/build/outputs/apk/debug/app-debug.apk` to
`provision/apk/lumora-household.apk`. Keep the same debug keystore
(`%USERPROFILE%\.android\debug.keystore`) so later builds update in place;
back it up with the private files.

Hard gate: `scripts/verify-lumora-household.sh apk <file>` refuses an APK that
lacks any required piece, and `scripts/verify-lumora-household.sh tv <ip>`
fails unless the TV shows every provider, favourite and plugin listed in
`provision/lumora/household-required.json`. `provision-tv.sh` runs both and
never uninstalls or clears the app. This gate covers the repo's tooling; a
person or agent with raw ADB access can still bypass it.

### Rebuilding it from the repo

`provision/lumora/household-7.5.patch` is the whole household change set
against upstream Lumora `268a9d2` (v7.5): the MMA/motorsports patch ported to
7.5, the seed and NFL stages (`HouseholdSeed.kt`), the behind-live-window
recovery, and a fix for an Android 9 crash (libwebp is not thread-safe there;
`PosterDiskCache` now encodes one image at a time below API 30, which stopped
the app dying during a full provider refresh on the TV).

```sh
git clone https://github.com/LumoraPlayer/Lumora custom-lumora75 && cd custom-lumora75
git checkout 268a9d2 && git apply ../lumora/household-7.5.patch
# private, not in Git: app/src/main/assets/household-seed.json and household-plugins/*.js
cp ../../provision/sports-fallback/scripts/../../lumora/plugins/*.js app/src/main/assets/household-plugins/
```

`household-nfl.json` (assets) names the NFL provider
(`provision/sports-fallback/nfl.m3u`, rebuilt daily) and the national NFL
channels to favourite. The NFL stage runs once, adds only, and puts the NFL
provider first.
