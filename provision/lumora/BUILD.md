# Building the patched Lumora (MMA + motorsports)

## The patch

`mma-motorsports-events-2026-11-07.patch` — 23 files, +661/-47, against
pristine Lumora v7.1 (`c0be28d`, `versionCode 71`). Verified to apply
cleanly to a pristine `c0be28d` checkout (`git apply --check`, 2026-11-07).

What it adds: MMA as a fixture-feed sport (API-Sports `/fights` on host
`v1.mma.api-sports.io`) and Formula 1 as a fixture-feed sport (`/races`),
plus MotoGP, NASCAR, IndyCar, WEC, WRC and Formula E as guide-only sports
with their own chips, icons and keywords. Event rows hide the score boxes
for fights/races. See the patch's CHANGELOG entry for the full list.

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

## Current build blocker (2026-11-07)

The APK is **not built yet**. This VM's sandbox blocks JVM loopback TCP
(`other_tcp` Deny), so the Gradle client cannot connect to its daemon and
the build cannot run here. Do not try to evade that gate. Build on a host
where Gradle loopback TCP is allowed (his PC, or any normal machine with
Android SDK + JDK 17).

## Install the built APK

```sh
adb connect <tv-ip>:5555
adb install -r app-release.apk
```

`install -r` only; sign-ins, plugins and settings stay. Keep the previous
APK for rollback: the stock fallback is the repo's `apps/lumora-7.1.apk`
(sha256 `5c66032eb9053e0c9e0a31e9e4ace9debbe4ee77f89eb4266467b474408a204a`).

Note the signing caveat above: a locally built APK signed with a new key
cannot upgrade the stock install in place. If the goal is an in-place
upgrade, the build must be signed with the same key that signed the
installed APK — for the stock release that is upstream's key, which is not
available. In practice the first patched build is a fresh install
(uninstall stock first, or accept the data wipe); provision afterwards from
`provision/lumora/README.md` again (plugins/add-ons live in the app's
private data dir, which an uninstall wipes).
