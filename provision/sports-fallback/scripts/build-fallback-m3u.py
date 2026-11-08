#!/usr/bin/env python3
"""Build the Sports fallback M3U.

Merges direct-URL public playlists into one M3U the TV can fetch from
GitHub raw if the primary VM aggregator (rebeliptv) is offline.

Sources (all direct URLs, no per-request headers needed, no live server):
  - Tubi US sports (BuddyChewChew generator) — FAST sports channels
  - The Roku Channel sports (BuddyChewChew generator) — FAST sports channels
  - Open TV Atlas English sports — unofficial restreams; sometimes carry
    live NBA/NFL/college games, but they are pirate restreams that die
    mid-game. Included because they are the only free source in this
    fallback that can carry an actual live game.

Deliberately NOT included: Samsung TV Plus and Pluto TV (already separate
providers in Lumora on the TV) and iptv-org sports (already a provider).
Duplicating them here would add nothing when flipping to this fallback.

Exit 0 if at least one entry was written, 1 if the merged playlist is empty.
A single source failing does not fail the run; it is logged and skipped.
"""
import json
import re
import sys
import urllib.request
from datetime import datetime, timezone

SOURCES = [
    {
        "name": "tubi",
        "url": "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/tubi_all.m3u",
        "sports_only": True,
    },
    {
        "name": "roku",
        "url": "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/roku_all.m3u",
        "sports_only": True,
    },
    {
        "name": "atlas-eng-sports",
        "url": "https://iman-py.github.io/open-tv-atlas/playlists/eng/sports.m3u",
        "sports_only": False,
    },
]

SPORT_RE = re.compile(r"sport|nfl|nba|mlb|nhl|football|basketball|baseball|hockey|soccer|boxing|mma|ufc|wwe|golf|tennis|racing|motorsport|f1|nascar", re.I)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "sports-fallback-builder/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status}")
        return resp.read().decode("utf-8", errors="replace")


def parse_m3u(text):
    """Return list of (extinf_line, url) pairs."""
    entries = []
    lines = [ln.strip() for ln in text.splitlines()]
    i = 0
    while i < len(lines):
        if lines[i].startswith("#EXTINF"):
            extinf = lines[i]
            j = i + 1
            while j < len(lines) and (not lines[j] or lines[j].startswith("#")):
                j += 1
            if j < len(lines):
                entries.append((extinf, lines[j]))
                i = j + 1
                continue
        i += 1
    return entries


def is_sports(extinf):
    # Check the group-title attribute first (authoritative); fall back to
    # the display name after the comma. Do NOT match against the whole
    # EXTINF line — logo URLs and other attributes contain sports words
    # on non-sports channels.
    m = re.search(r'group-title="([^"]*)"', extinf)
    if m:
        return bool(SPORT_RE.search(m.group(1)))
    name = extinf.split(",", 1)[1] if "," in extinf else extinf
    return bool(SPORT_RE.search(name))


def main():
    now = datetime.now(timezone.utc)
    merged = []  # (extinf, url, source)
    seen_urls = set()
    stats = {"generated_utc": now.isoformat(), "sources": {}, "total": 0}

    for src in SOURCES:
        try:
            text = fetch(src["url"])
            entries = parse_m3u(text)
        except Exception as exc:  # noqa: BLE001 - one bad source must not kill the run
            print(f"[warn] {src['name']}: fetch/parse failed: {exc}", file=sys.stderr)
            stats["sources"][src["name"]] = {"status": "failed", "error": str(exc), "kept": 0}
            continue
        kept = 0
        for extinf, url in entries:
            if src["sports_only"] and not is_sports(extinf):
                continue
            if url in seen_urls:
                continue
            seen_urls.add(url)
            merged.append((extinf, url, src["name"]))
            kept += 1
        stats["sources"][src["name"]] = {"status": "ok", "fetched": len(entries), "kept": kept}
        print(f"[ok] {src['name']}: {len(entries)} fetched, {kept} kept")

    stats["total"] = len(merged)
    if not merged:
        print("[error] merged playlist is empty", file=sys.stderr)
        json.dump(stats, open("stats.json", "w"), indent=2)
        return 1

    out = ["#EXTM3U"]
    out.append(f"# Generated {now.strftime('%Y-%m-%d %H:%M UTC')} — Sports fallback M3U")
    out.append("# Primary is the VM rebeliptv aggregator; use this only if the VM is down.")
    out.append("# Open TV Atlas entries are unofficial restreams: they may carry live")
    out.append("# games but die mid-game. Tubi/Roku entries are FAST shoulder programming.")
    for extinf, url, _src in merged:
        out.append(extinf)
        out.append(url)
    open("sports-fallback.m3u", "w").write("\n".join(out) + "\n")
    json.dump(stats, open("stats.json", "w"), indent=2)
    print(f"[done] {len(merged)} entries -> sports-fallback.m3u")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
