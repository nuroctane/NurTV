# Custom client work in progress

The `custom-*/` folders are upstream clones and are not in git. Our changes live in
`patches/`: clone the upstream URL at the commit named below, then `git apply` the patch.

Do not add these builds to the golden profile until they have been tested on a
TV. Upstream APKs remain the default provisioned clients.

## Lumera Household prototype

- Source: `custom-lumera/` = https://github.com/LumeraD3v/Lumera at `b0e4425` (tag `v0.1.8-beta`) + `patches/lumera-household.patch`.
- APK: `custom-lumera/app/build/outputs/apk/debug/app-debug.apk`.
- SHA-256: `1401df9db0d5c172e39fec1dea17fb0a5c7b027b5fe3d7e89d17935c6a05631f`.
- App ID: `com.lumera.app.household`, installed separately from `com.lumera.app`.
- New profiles created from scratch get Cinemeta plus the six manifests in
  `app/src/main/assets/household-addons.json`. Existing profiles are not reseeded.
  Manifests contain public URLs, not accounts. These are snapshots; hosts can
  change or disappear. Torrentio and Comet may expose IP addresses to peers.
- Build is debug-signed with the local Android debug key. It is a prototype,
  not a release artifact; preserve the key for upgrades or establish a dedicated
  signing key before relying on it. Upstream automatic update checks are disabled
  in the debug build because upstream APKs cannot upgrade this signing identity.
- Build succeeded and the separate APK installed on the source TV. First-run
  profile creation, source list, removal persistence, and playback have **not**
  been verified; do those before including it in provisioning.

Build from `custom-lumera/`, with Android SDK 36 and JDK 17 or later:

```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
powershell -NoProfile -File "$env:USERPROFILE\.agents\lowcpu.ps1" cmd.exe /c gradlew.bat :app:assembleDebug --max-workers=4 --no-daemon
```

The source checkout is a separate Git repository. Keep its changes, the manifest
asset, and the signing key backed up together; the built APK alone is not a
reproducible source backup.

## What moves a TV's add-ons, by client

| Client | How its add-ons reach a new TV |
|---|---|
| CloudStream | `scripts/capture-app-settings.sh` backup: exact repos + downloaded plugins. Fallback with no source TV: CloudStream Household below |
| Zangetsu | the same backup: provider repo + installed providers. No custom build (see below) |
| Watchbox | extension APKs via `apply-sources.sh`; repo list via the backup |
| SmartTube, S0undTV | the same backup: ad-block / SponsorBlock / Luminous proxy settings. Upstream APKs kept, so in-app updates still work |
| Lumera | `allowBackup` off. Lumera Household prototype, or manual entry |
| Arvio | `allowBackup` off and no matching source (below). Manual entry |
| Atlantic | content plugin is built in |

## CloudStream Household

- Source: `custom-cloudstream/` = https://github.com/recloudstream/cloudstream at `3796406` (v4.8.0) + `patches/cloudstream-household.patch`.
- Build: `:app:assembleStableDebug`, app ID `com.lagradost.cloudstream3.household`,
  label "CloudStream Household", installs beside upstream CloudStream.
- APK: `custom-cloudstream/app/build/outputs/apk/stable/debug/app-stable-debug.apk`,
  SHA-256 `7cfc779f9beae8cbc05b94e948d0f596c035a17370666a8d0bd6e35a167d8d98`
  (built 2026-10-30). Contains `assets/household-repos.json`. First-run seeding
  and plugin download have **not** been run on a TV yet.
- Change: `HouseholdSetup.kt` + 4 lines in `MainActivity.kt`. On first launch it
  adds the repos in `app/src/main/assets/household-repos.json` (official
  `recloudstream/extensions` and Phisher), sets provider language to `en` if none
  was chosen, and downloads those repos' English plugins **once**. It never runs
  again, so removed plugins stay removed. Upstream auto-download stays off.
- Debug-signed with the local Android debug key; the in-app updater is a no-op in
  debug builds. Not installed on the TV and not in provisioning: with a working
  source TV the backup is exact; this is for a setup with no source TV.

Build (JDK 17 toolchain, Android SDK 36), from `provision/`:

```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"; $d = "$PWD\custom-cloudstream"
powershell -NoProfile -File "$env:USERPROFILE\.agents\lowcpu.ps1" "$d\gradlew.bat" -p $d :app:assembleStableDebug --max-workers=4 --no-daemon
```

## Not built

- Zangetsu: Flutter app; this PC has no Flutter SDK, and the backup already carries
  the exact providers with the upstream signature intact. `custom-zangetsu/` is
  unmodified upstream v2.3.4. Seeding would go in `ProviderReposRegistry`
  (`lib/core/provider/provider_repo_registry.dart`, Hive box `provider_repos`).
- ARVIO: `custom-arvio/` is a public mirror reporting v1.9.982, older than the
  installed v2.3; a build from it would be a different, older app.
- SmartTube and S0undTV: rebuilding would change their signatures and break in-app
  updates; S0undTV is closed source. Their settings move with the backup instead.
