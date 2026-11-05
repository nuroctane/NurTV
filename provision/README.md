# provision — put this setup on another TV of the same model

Two commands, both driven by `provision/golden-state.json`:

```sh
./scripts/capture-tv.sh           <working-tv-ip>  # TV -> repo (read-only on the TV)
./scripts/capture-app-settings.sh <working-tv-ip>  # app state -> private/ (one press on the TV)
./scripts/provision-tv.sh         <new-tv-ip>      # repo -> new TV, everything
```

`capture-app-settings.sh` captures data for apps whose setup lives
in private data: SmartTube's ad/SponsorBlock/shorts settings, S0undTV's Luminous
ad-free proxy slots, CloudStream's repos **and downloaded plugins**, Zangetsu's
provider repo **and installed providers**, and Watchbox's repo list. It runs
`adb backup` (the TV asks "Back up my data": press it, no password), strips caches,
webview cookies and anything that looks like a sign-in (`scripts/app_settings.py`
prints every dropped file and key), and writes `private/app-settings/app-settings.ab`.
This filtering is heuristic, so the private backup may still contain sensitive data.
Restoration is opt-in and has not been verified on another TV. Run the
capture when nothing is playing: the backup force-stops those apps.

Capture the working TV after app or launcher changes. Provisioning installs the
captured APKs and settings on a matching TV; app-private add-ons and sign-ins still
need the manual steps below. `capture-tv.sh` never writes to the TV and
`provision-tv.sh` never uninstalls anything.

## What the new TV needs first

1. `Settings > My Fire TV > About` → tap **OK 7 times** → **Developer Options** → *ADB debugging* **on**.
2. Same LAN as this machine.
3. `./scripts/connect.sh <ip>` and accept **Allow ADB debugging?** on the TV.

Then:

```sh
./scripts/provision-tv.sh <ip>                  # the whole thing (~5 min, 2 reboots)
./scripts/provision-tv.sh <ip> --dry-run        # say what would happen, touch nothing
./scripts/provision-tv.sh <ip> --verify-only    # change nothing, only check
./scripts/provision-tv.sh <ip> --skip-system    # apps + config only, no debloat/DNS/HOME
./scripts/provision-tv.sh <ip> --restore-app-settings  # also restore the private backup
python scripts/source-checklist.py               # current manual add-on checklist
```

The profile is **model-specific** — HDMI input ids and the debloat list are not the
same across Fire TV models — so provisioning refuses unless the new TV reports the
same `ro.product.device`, `ro.product.model` and sdk as the captured one. `--force`
overrides that, deliberately.

## What it actually does

| Step | Detail |
|---|---|
| guard | refuses a different model (`hazel / AFTMD001 / sdk 28`), unless `--force` |
| backup | `scripts/backup-packages.sh` on the *target* first: a new `backups/<stamp>/` undo sheet |
| app layer | every package in the golden state, in order: launcher, DNS filter, then apps. Each APK is hash-checked against the repo **before** install and the installed base APK is pulled back and hash-checked **after**. Already-current packages are skipped. |
| system layer | `cleantv/scripts/all.sh -y`: debloat, lockdown, on-device DNS filter, HOME takeover (`cleantv/cleantv.conf` holds the household answers) |
| extra debloat | any package the working TV has disabled that CleanTV's scripts do not touch |
| config | `apps/home.conf` → `files/home.conf`, `apps/art/*.png` → `files/art/`, the applied wallpaper → `files/wallpaper.jpg` |
| restart | launcher force-stop + start so the new art is read (art is cached per tile), then the accessibility Guard is rebound |
| media sources | `scripts/apply-sources.sh`: the six Watchbox extension APKs in `provision/sources.json`, hash-checked |
| app state | Opt in with `--restore-app-settings`: Android restore may replace settings on the target and requires a TV confirmation. The sanitized backup has been captured, but restoring it to another TV has not been verified. Arvio, Lumera and Atlantic are not included. |
| verify | versions + APK hashes, `home.conf` by key/value, art by bytes, the VPN/alarm/accessibility settings and disabled list; a normal run also presses **HOME** to test the takeover |

Exit status is non-zero if any check fails; every failure is printed as a `!` line.

`provision/apk-updates.json` can override a captured app with a newer, locally
verified APK. The captured `golden-state.json` still describes the source TV;
provisioning and `--verify-only` compare against the override where one exists.
SmartTube 32.68 and Atlantic 1.0.9 were installed on the source TV and recaptured;
their entries no longer need overrides. The captured SmartTube APK supports the
source TV's 32-bit ARM architecture. After updating and recapturing a staged app,
remove its corresponding override. APK hash checks still run before installation.

## What is in this directory

```
provision/golden-state.json   what the working TV has: device guard, every package
                              with version, install mode, APK path and sha256, the
                              disabled list, and the settings the scripts leave behind
provision/sources.json        Watchbox extension APKs (installed on every provision)
                              plus the in-app repo URLs capture cannot see
provision/apk/<pkg>.apk       byte-exact APKs for anything the repo did not already
                              have (currently Kick, Rumble, X, SmartTube, DNS filter)
```

`golden-state.json` references APKs that are already elsewhere in this folder rather
than copying them, so `apps/*.apk`, the wrapper builds in `apps/webwrap/out/` and
`apps/cleantv-home.apk` are used in place. Only genuinely missing APKs land in
`provision/apk/` (~80 MB today: SmartTube alone is 35 MB, and it is re-fetchable from
the checksum-pinned URL in `cleantv/scripts/youtube.sh` if you ever want the space back).

## Never compare home.conf by bytes

The launcher rewrites its own copy: it keeps its header, drops every other comment and
does not reorder. `apps/home.conf` is the same keys **plus the notes that explain this
household**, so capture merges values into the repo file and verification compares
key/value maps (`scripts/home_conf.py diff|merge`). Byte comparison would report a
difference on every run.

## What is deliberately *not* copied

| Not copied | Why |
|---|---|
| accounts and sign-ins (S0undTV/Twitch, Kick, Rumble, X, Sozo, Atlantic, Prime, Netflix) | not intentionally migrated; the backup sanitizer is heuristic and may retain sensitive data |
| Aerial Views as screensaver (`secure screensaver_*`) | four adb lines in apps/manifest.md "APK installs: Aerial Views, X-plore" |
| sign-in material inside app state | the sanitizer attempts to remove credentials; it cannot guarantee every credential is removed. Treat the backup as sensitive, and expect to sign in again |
| Arvio add-ons | `allowBackup` is off, and `stremio://addon/…` was delivered then dropped. Add the manifests in Settings → Addons → Add Addon; the current list is in `sources.json` |
| Lumera add-ons | `allowBackup` is off. Enter the manifests from `sources.json`, or use the Lumera Household prototype (provision/CUSTOM-CLIENTS.md), which seeds them into new profiles |
| Netflix's updated system app | the Appstore restores it on any Fire TV of this model; capture skips it |
| Appstore ownership | Kick/Rumble/X are installed from their pulled APKs, so they run, but the Appstore will not offer updates for them as it does for a store-installed copy |

Left for a human after a successful run: the sign-ins above and the Arvio and
Lumera add-on lists in `provision/sources.json`. SmartTube/S0undTV settings and
CloudStream/Zangetsu sources are manual unless the private backup is restored;
verify them afterward because that restore has not been tested. Run
`python scripts/source-checklist.py` for the URLs and provider names.
Confirm each installed source in its app and test playback: these third-party
services can change, and a reachable manifest does not guarantee a working stream.
Watchbox's repo link can optionally be opened with `./scripts/apply-sources.sh <ip> --with-intents`;
finish any confirmation in the app. The extension APKs themselves install automatically.

## Launcher signing key

`apps/cleantv-home.apk` is `tv.cleantv.home` v1.4 (versionCode 6), signed with
`private/cleantv.keystore` — `CN=CleanTV`, SHA-256
`40:DB:8E:0A:AE:E8:A8:7D:B9:66:CB:5C:8C:BC:19:08:2D:6C:6F:47:38:13:63:EE:41:8A:B9:4B:C3:4A:86:0E`.
That key exists, so a rebuild upgrades in place. Keep it backed up: a different key cannot
upgrade an installed launcher, only replace it via uninstall/reinstall.

The **previous** launcher (`tv.dumbtv.home` v1.3, versionCode 5) was signed by a key that is
gone — not under `firetv/`, and `%USERPROFILE%\.android` holds only the stock debug
certificate. That is why the rename to a new application id came with a new key rather than
an in-place upgrade. Its APK is kept for rollback:
`provision/apk/legacy-launcher-v1.3-code5-tv.dumbtv.home.apk` (sha256 `87fbd89d…`) — pull it
in by hand with `adb install -r` if the current launcher ever misbehaves; provisioning itself
never installs it, because a rollback would also restore the old application id.

`./scripts/build-launcher.sh` regenerates the key from scratch if `private/cleantv.keystore`
is missing, and prints the new fingerprint. See private/README.md.

## One thing that interrupts playback

A normal provisioning run **presses HOME** to test the takeover. `--verify-only`,
`--dry-run`, and `--skip-system` do not press HOME; check it manually if needed.

## Live state at capture time

`hazel / AFTMD001`, Fire OS 7.7.1.7 (sdk 28), 15 packages, 39 disabled packages,
wallpaper `apps/wallpapers/dark-waves.jpg`. `provision/golden-state.json` carries the
`captured_at` stamp and is the authority — it changes every time capture runs.

Verified by `./scripts/provision-tv.sh <tv-ip> --verify-only` against the source
TV (pass the address; do not reuse an old one): every package by versionCode and pulled-APK sha256, `home.conf` by key/value, both
art files by bytes, the 39-package disabled list, the VPN/alarm/accessibility settings,
and a real HOME press landing back on CleanTV. Also checked: capture is idempotent (a
second run reports "unchanged" everywhere), `--dry-run` writes nothing, an unreachable
TV exits 1 with one clear line, and both scripts behave the same with the caller having
exported `MSYS_NO_PATHCONV=1`.
