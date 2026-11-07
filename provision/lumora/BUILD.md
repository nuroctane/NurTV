# Building the patched Lumora (MMA + motorsports)

## The patch

`mma-motorsports-events-2026-11-07.patch` — 40 files, +1859/-48, against
pristine Lumora v7.1 (`c0be28d`, `versionCode 71`). Verified to apply
cleanly to a pristine `c0be28d` checkout (`git apply --check`, 2026-11-07).

What it adds: MMA as a fixture-feed sport (API-Sports `/fights` on host
`v1.mma.api-sports.io`) and Formula 1 as a fixture-feed sport (`/races`),
plus MotoGP, NASCAR, IndyCar, WEC, WRC and Formula E as guide-only sports
with their own chips, icons and keywords. Event rows hide the score boxes
for fights/races. Plus a built-in IRC client for the ModdingCartel fight
chat (irc.obnoxious.lol:6697 TLS, channel configurable, nick default
`nuroctane`) and the behind-live-window player recovery from the Media3
demo app. See the patch's CHANGELOG entry for the full list.

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
