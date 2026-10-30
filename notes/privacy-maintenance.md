# Privacy and maintenance

The launcher, Fire OS, native apps, and websites have separate trust boundaries.
CleanTV has no INTERNET permission. Its accessibility service observes window
changes and declares canRetrieveWindowContent=false. This does not prevent Fire
OS or streaming apps from collecting data.

## Wrapper defaults, version 3.9.1

- Fresh DEX compilation on every build; mandatory JavaScript syntax and behavior
  checks and pure-Java navigation tests. Each APK carries its source SHA-256 in
  activity metadata; its JSON receipt records the source and APK hashes.
- Exact approved HTTPS hosts for top-level navigation, redirects and popups.
  Popup requests require user activation. Third-party HTTPS player frames and
  media requests remain possible; navigation restrictions are not a tracker filter.
- Third-party cookies, HTTP/mixed content, and detailed diagnostics are off.
  JavaScript, first-party cookies and local storage remain enabled for playback.
- No file/content access; Safe Browsing enabled where the engine supports it.
  Uses the actual WebView user agent instead of claiming a newer Chrome version.
- Sandbox removal and chat scans are gated by policy. No current wrapper has a
  sandbox exception; its approved sandbox-host list is empty. Only StreamEast
  enables chat hiding. Hiding a frame is cosmetic and does not prevent its requests.
- Hold MENU for site settings, Reload, or Clear site data. Clearing uses Android's
  own app-data reset, including cookies, IndexedDB, service workers and caches. It
  signs out and closes only that wrapper. Tap MENU for fullscreen.
- Fullscreen pins keep controls with the player. Explicit fullscreen keeps the
  display awake even if cross-origin playback cannot be inspected. Polling stops
  while the activity is paused. Decoder activity alone does not prove usable UI.
- Detailed logging is opt-in. Page error text and page-provided URLs are never
  copied to logcat; diagnostics accept only selected numeric/status markers.

apps.txt has seven pipe-separated columns:
slug|package|label|HTTPS URL|icon|comma-separated flags|additional exact navigation hosts.
Flags: nochat, legacy-http, third-party-cookies, diagnostics. An exception must
record the failing site, reason, observed requirement, and a retest date here.
legacy-http permits cleartext media and WebView's compatibility mixed-content
mode, not unrestricted mixed content. It never permits HTTP top-level navigation.
No such HTTP or cookie exceptions are currently enabled. If a site fails, inspect
its actual dependency before enabling an exception; do not relax every wrapper.

Navigation exception, observed 2026-10-27: StreamEast redirects its initial page
to HTTPS auth.streamea.st. That exact host is approved only for StreamEast, with
no cookie or HTTP relaxation. Retest by 2026-11-26. This permits the redirect flow;
it is not an endorsement of the site's privacy policy. Blocked top-level links
and load errors show a native message instead of an unexplained blank screen.

## Install, validation and rollback

Build in Git Bash: cd apps/webwrap && ./build.sh.
Run from the project root:

    python scripts/update-wrappers.py --serial <tv-ip>:5555

The installer validates receipts, backs up every current APK before changing any,
updates with adb install -r, then pulls installed APKs back and compares SHA-256.
A signing mismatch stops installation; no uninstall fallback erases app data.
It does not launch apps or reboot. Previous APKs and receipts are in the printed
backups/wrappers-* directory. A partial multi-app update is reported as an error;
already-updated apps are not silently rolled back.

To return to an older signed APK, use adb -s <tv-ip>:5555 install -r -d <backup.apk>.
Fire OS may refuse a downgrade for a non-debuggable app. Do not uninstall to work
around that: rebuild the backed-up source with a higher versionCode and the same
key, or investigate the playback regression. APK backups do not include private
site data. Keep a source backup alongside the APK backups before future releases.

Validate each affected site with real content: first frame and sound, fullscreen
with usable controls, BACK exit, source switching, and repeat after sleep/wake.
A layout screenshot and decoder log are complementary evidence; neither alone
proves the requested playback experience. Record failures instead of calling them
fixed based on a catalog page or stream dimensions.

## DNS and traffic verification

    ./scripts/privacy-check.sh <tv-ip>

This is read-only: provider identity, selected privacy settings, always-on/lockdown
values, disabled-package count, and one allowed/blocked DNS pair. It neither
launches apps nor stops the filter. Passing means only those checks passed.

The configured personalDNSfilter upstream is UDP/53 to the router unless changed.
That is not proof of encrypted DNS upstream. An Amazon-only blocklist does not
cover third-party website tracking. DNS cannot reliably block first-party
telemetry sharing playback hosts, direct IP connections or embedded DoH.

Always-on VPN and VPN lockdown are different. Do not enable lockdown blindly on
this DNS-only VPN: ordinary playback or management connectivity may break. Router
traffic capture is needed to check boot/wake leaks, IPv6, direct IP and alternate
DNS. Capture destination/port summaries, minimize retention, and keep captures
private. Test idle, playback, reboot, wake, and filter failure separately, with a
recovery route available. ADB-only DNS checks are not a traffic audit.

Keep network ADB on a trusted management network. After maintenance, disable it
in the TV's developer settings or restrict TCP/5555 to the management computer at
the router. Launcher and DNS filtering do not require a persistent PC connection.

With no always-on host, keep the on-device resolver. Router enforcement becomes
useful if the router itself can run filtering or an always-on resolver is added.
Encrypted DNS hides queries in transit; its resolver still receives them. A VPN
also adds a provider and does not remove telemetry embedded in an app's HTTPS.

## Controlled updates and recovery

OTA blocking is an intentional compatibility hold, not a security benefit. For a
maintenance window: save APKs/settings/package state, review official firmware
and WebView updates, temporarily allow only required update paths, update, then
retest HOME, inputs, remote, playback and DNS. Restore the selected block policy
afterward. No automatic firmware update or VPN change is part of this hardening.

emergency-restore.sh detaches the CleanTV HOME hook and restores Amazon HOME;
it leaves OTA and Appstore policy unchanged. It does not factory-reset the TV.

New package-disable operations record the exact PackageManager override (0–4)
once in cleantv/report/package-states-before.tsv. restore.sh uses that override
instead of always enabling the package. Missing settings in an original settings
snapshot are deleted rather than replaced with guessed defaults. Legacy installs
without the package ledger still use enable defaults and print a warning: their
original overrides cannot be reconstructed exactly. App-op/network-policy legacy
reset behavior and externally uninstalled apps are not a full machine snapshot.

## Private material

Signing keys live outside the project in ~/.local/share/firetv-keys/. Override
WEBWRAP_KEYSTORE and WEBWRAP_KEYPASS locally if needed. Preserve the original key;
generating a replacement breaks in-place updates. Restrict access and keep an
encrypted offline backup. A default password is not protection from a local user
who can read the key. Do not publish backups, raw settings, Wi-Fi/account details,
serial numbers, logcat dumps, or signing material. .gitignore is an additional
guard, not protection against manually sharing the entire directory.

S0undTV ad-removal proxies add another party to playlist requests. No proxy has
been configured by this pass. Assess destinations, token handling, logs and
retention before choosing one. DNS blocking cannot selectively remove video ads
stitched into the same delivery stream.
