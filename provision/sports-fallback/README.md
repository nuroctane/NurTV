# sports-fallback

Fallback sports M3U for the TV (Sports / Lumora), for when the primary
VM aggregator (rebeliptv, hosted on a private VM) is offline.

## The URL the TV uses

```
https://raw.githubusercontent.com/nuroctane/NurTV/main/provision/sports-fallback/sports-fallback.m3u
```

Add it as a second M3U provider in Lumora and keep it alongside the
primary rebeliptv provider, so flipping to it is a provider switch, not
a re-add.

## What is in it

A merged playlist built once a day (17:00 UTC / 11:00 CT) by GitHub
Actions, plus on-demand runs from the Actions tab. Sources:

- **Tubi US sports** and **The Roku Channel sports** — FAST channels
  (shoulder programming, highlights, classics, studio shows).
- **Open TV Atlas English sports** — unofficial restreams. These are the
  only entries that sometimes carry an actual live NBA/NFL/college game,
  but they are pirate restreams: they die mid-game, buffer, and vanish
  without warning.

Deliberately not duplicated here: Samsung TV Plus, Pluto TV, and
iptv-org sports, which are already separate providers in Lumora.

## What it is not

This is a **degraded** fallback, not a replacement for the primary.
It cannot reliably deliver live games: the primary aggregator does that
by proxying and re-resolving streams live; a once-a-day static file
cannot. The committed playlist contains unofficial restream URLs.

Note: this lives in NurTV because the GitHub App cannot create a new
repo on its own. The safer long-term home is a separate repo
(e.g. `nuroctane/sports-fallback`), so a takedown — if one ever comes
for the restream URLs — hits only that repo. Moving it is a file
relocation plus a workflow path change; the Lumora provider URL would
change to the new repo's raw URL.

## Cost

Public repo: GitHub Actions is free. One run a day, a few minutes each.

## Files

- `sports-fallback.m3u` — the generated playlist (committed by Actions).
- `stats.json` — per-source counts from the last run.
- `scripts/build-fallback-m3u.py` — the merge script (Python stdlib only).
