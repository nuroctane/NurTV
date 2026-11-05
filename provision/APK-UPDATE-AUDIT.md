# APK update audit — 2026-10-30

The update audit was followed by an in-place installation and capture on the
source TV. The earlier connection failure was an ADB connection error, not proof
that the TV was offline.

- SmartTube stable 32.56 → 32.68: official v7a APK installed and captured.
- Atlantic 1.0.6 → 1.0.9: publisher manifest APK installed and captured.
- Both APKs match the publisher's SHA-256, the existing app's signing
  certificate, the expected package, Android SDK 28 and 32-bit ARM. Installation
  and playback has not yet been tested.
- ARVIO 2.3, CloudStream 4.8.0, Lumera 0.1.8-beta, Watchbox 4.14.12,
  Zangetsu 2.3.4, Aerial Views 1.8.5 and S0undTV beta 146 match the latest
  releases available through their publishers' release endpoints at audit time.
- The six Watchbox extension version codes match the yuzono repository index.
- X-plore 4.46.00 matches the publisher's listed download at audit time.
- Kick, Rumble, X, Sozo, and personalDNSfilter have not been confirmed current;
  a trustworthy newer matching APK was not established in this pass. Local
  wrappers and the launcher are custom builds, not upstream release APKs.

Sources: https://github.com/yuliskov/SmartTube/releases/tag/32.68s,
https://atlantic.st/dl/app/manifest.json, https://github.com/ProdigyV21/ARVIO/releases/latest,
https://github.com/recloudstream/cloudstream/releases/latest,
https://github.com/LumeraD3v/Lumera/releases/latest,
https://github.com/Nicartjay/Watchbox-Android/releases/latest,
https://github.com/Spyou/Zangetsu/releases/latest,
https://github.com/theothernt/AerialViews/releases/latest,
https://github.com/S0und/S0undTV/releases/latest,
https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json,
https://www.lonelycatgames.com/apps/xplore.
