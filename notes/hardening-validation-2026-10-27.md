# Hardening validation — 2026-10-27

## Installed artifacts

All four wrappers are version 3.9.1 (versionCode 31). The installer compared each
installed APK byte-for-byte with its local build receipt after installation.
Their shared source SHA-256 is
823c765cf6bac333584f398be5f85a11cb460bd56d6bf138aad0d45972ff71d6.

Original pre-hardening APKs: backups/wrappers-2026-10-27_123835/.
Final-install receipts and previous APKs: backups/wrappers-2026-10-27_124602/.
These private directories also contain the replacement source archive. The first
source archive contains the first hardened revision, not the pre-hardening source.

## Automated checks

- 80 existing and updated CleanTV tests pass against fake devices under WSL.
- Two additional tests verify that the first package state is retained and an
  unreadable original state stops mutation. Both pass.
- Actual embedded JavaScript payloads pass syntax checks. Executed EXTRAS tests
  cover disabled feature timers, chat-only activation, and keeping unapproved
  iframe sandboxes intact.
- Java navigation-policy tests cover exact hosts, allowed exceptions, disallowed
  ports/schemes/subdomains, and authority/user-info confusion.
- All inspected shell scripts pass bash -n; 29 device catalog files validate.
- Final live verification exposed an old verifier label: the installed service is
  CleanTV home button, while the parser recognized only CleanTV home button. The
  parser now accepts both exact labels. Two new tests pass for the CleanTV label
  and rejection of a similarly named service. Total unique Python checks: 84.

## TV observations

- Amazon WebView identifies as 138.amazon-webview-v138-7204-tv.7204.244.304.
  This is the provider's reported version, not an independent security assessment.
- Always-on VPN is dnsfilter.android. Lockdown is unset. Selected Amazon usage
  reporting values are 0, limit-ad-tracking is 1, and 39 packages are disabled.
- Allowed DNS lookup resolves while the sampled Amazon update hostname is blocked,
  both before and after wrapper installation.
- frameX, Fights and MMA Stream render with third-party cookies and HTTP disabled.
  MMA Stream's catalog includes old/upcoming events; a catalog is not playback.
  Fights shows its reconnecting state; this does not establish a working live feed.
- frameX playback advanced to 1:06. MENU fullscreen and media pause exposed the
  complete title, timeline, subtitles and bottom controls in the captured viewport.
  This media check used the initial 3.9 build; 3.9.1 adds load-status UI and the
  StreamEast redirect exception without changing that playback implementation.
  A black captured video surface alone was not treated as a failed player.
- StreamEast initially redirected to auth.streamea.st and was blocked by the new
  top-level host policy. That exact HTTPS host was added only for StreamEast;
  version 3.9.1 then rendered its catalog and selected event. The selected feed
  displayed a premium gate, so it was not counted as successful video playback.
  No purchase, login, proxy or general cookie/HTTP relaxation was performed.
- Holding MENU opens the native Reload / Clear site data menu. It was dismissed
  without clearing user data. The actual data-reset action was not exercised.

## Limits

No reboot, firmware update, DNS service failure, router enforcement or packet
capture was performed. Long playback, sound at the speakers, sleep/wake leakage,
IPv6/direct-IP/embedded-DoH bypass and all alternate sources remain unverified.
No claim of zero telemetry is supported. Full rollback was tested on fake TVs,
not applied to the household TV. Legacy installs lack an exact original package
ledger; app-op/network reset behavior retains the documented legacy limitations.

At wrap-up the TV stopped responding to network ADB, and a reconnect timed out.
The final full live verify rerun therefore could not complete. Earlier live checks
confirmed DNS filtering and HOME landing; the corrected label parser passed its
regression tests. Installed APK hash verification completed before the disconnect.
