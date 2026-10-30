# firetv — living-room TV project

TCL Q6 Fire TV, Fire OS 7 / Android 9 (SDK 28). The setup uses reversible ADB
changes, CleanTV HOME, personalDNSfilter, native TV clients, and six website
wrappers. It does not root or replace firmware.

## Current configuration

- CleanTV: local launcher with no internet permission; HOME accessibility hook.
- personalDNSfilter: on-device Amazon-focused DNS filtering. Upstream defaults to
  the router over UDP/53. This is not a full firewall or an anonymity service.
- Wrappers: frameX, Fights, MMA Stream, StreamEast, AnimeHeaven, Miruro. Security
  defaults and build instructions are in apps/webwrap/README.md.
- Native apps and historical additions/removals: apps/manifest.md. The apps.txt
  wrapper registry and live package inventory take precedence over old prose.
- No always-on DNS host. adguard/ remains a lab option; PS5 guidance is in
  notes/ps5-adguard.md.

## Connect and inspect

Use Git Bash from this directory. Enable ADB on the TV and authorize this computer.
Supply the actual TV IP explicitly; scripts no longer embed a household address.

    ./scripts/connect.sh <tv-ip>
    ./scripts/backup-packages.sh <tv-ip>
    ./scripts/privacy-check.sh <tv-ip>

privacy-check.sh is read-only. Its sampled DNS checks do not establish that all
telemetry is blocked. Device identifiers and raw backups must stay private.

## Import this setup onto another TV of the same model

The apps and supported device settings can be provisioned to a second TV of the
same model. App-private add-ons and sign-ins require manual setup; see
provision/README.md for the coverage table and checklist.

    ./scripts/capture-tv.sh   <working-tv-ip>   # TV -> repo, read-only on the TV
    ./scripts/provision-tv.sh <new-tv-ip>       # repo -> new TV, then verify
    python scripts/source-checklist.py           # manual app add-on steps

`capture-tv.sh` is what keeps this true: run it after changing anything on the TV
(home screen order, tile art, a new app, a new wallpaper) and `provision/` follows.
Provisioning refuses a different model unless forced — HDMI input ids and the
debloat list are model-specific.

## Change the baseline

Read cleantv/AGENTS.md. Preserve current settings/package state and review saved
preferences before applying a full debloat pass. Avoid rerunning the entire pass
just to update wrappers. Keep Prime, Alexa and app-removal choices explicit.

    export ADB_SERIAL=<tv-ip>:5555
    cd cleantv
    ./scripts/preflight.sh --dry-run
    ./scripts/configure.sh
    ./scripts/all.sh
    ./scripts/verify.sh

New disable operations record the original PackageManager override once.
Old installs without those records cannot claim exact package rollback.

## Update wrappers

    cd apps/webwrap
    ./build.sh
    cd ../..
    python scripts/update-wrappers.py --serial <tv-ip>:5555

The installer backs up old APKs first and verifies each installed APK by hash.
It does not launch apps or reboot the TV. Test real playback and controls afterward.

## Recovery

    ./scripts/emergency-restore.sh <tv-ip>

This detaches the CleanTV HOME hook, re-enables Amazon HOME, and reboots. It does
not enable OTA or factory-reset the TV. Full legacy reset: cleantv/scripts/restore.sh;
read its printed plan and limitations first.

See notes/privacy-maintenance.md for wrapper policies, compatibility exceptions,
privacy limits, firmware maintenance, validation, rollback, and key handling.
Signing material belongs in `private/` (ignored by git) — see private/README.md.

## Vendored upstreams

`cleantv/` (fork of humblemuzzu/dumbtv) and `firestrip/` (WB2024/firestrip) are
tracked directly in NurTV. Their original histories are parked in
`.nur/nested-git/` (not in git). To pull upstream changes into cleantv:

```sh
git --git-dir=.nur/nested-git/cleantv.git --work-tree=cleantv fetch upstream
```
