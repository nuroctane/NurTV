# Building the patched Lumora (MMA + motorsports)

## The patch

`mma-motorsports-events-2026-11-07.patch` — 40 files, +1865/-48, against
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
build-tools 36.0.0). Fourth build run went green on release:
`BUILD_EXIT=0`, APK `C:\Users\david\Laboratory\lumora-patched-7.1.apk`
(39,952,866 bytes), sha256
`ed8a180e5051e3ccc5ec50eab5e0e2240cd79857b969c935eb35c3750ac23fc9`,
package `com.lumora`, versionCode 71001, versionName 7.1. Installed on the
TV the same day as a fresh install (stock uninstalled first).

Release signing key: `C:\Users\david\Laboratory\lumora-release.jks`
(RSA 2048, alias `lumora`, generated 2026-11-07), password only in
`C:\Users\david\Laboratory\lumora-keystore.properties`. Reuse it for later
patched builds so they upgrade this one in place. The release is
debuggable on purpose so the app private data can be provisioned with
`adb shell run-as`.

Unit tests did not go green in that run: the test compile failed on
nullability in the new `IrcMessageTest` (parse returns nullable, test
accessed it directly). Fixed in the patch (`!!` on the parse calls); a
rebuild to confirm the tests pass has not run yet. Main code compiled
clean in both debug and release.

## Install the built APK

```sh
adb connect <tv-ip>:5555
adb uninstall com.lumora
adb install app-release.apk
```

Uninstall first: a locally built APK signed with a new key cannot upgrade
the stock install in place, so the first patched build is a fresh install
and the app private data is wiped. Provision afterwards from
`provision/lumora/README.md` again (plugins/add-ons live in the app
private data dir, which an uninstall wipes). Later builds signed with the
same local key upgrade in place with `install -r`.
