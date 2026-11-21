#!/usr/bin/env python3
"""Build nfl.m3u: every public channel that can carry an NFL game and is streaming now.

Run from provision/sports-fallback after build-fallback-m3u.py. Pulls the public
playlists the TV already uses, keeps NFL-capable names (see nfl.py), checks each stream
answers with an HLS playlist, and writes them under group-title="NFL", national carriers
first. Keeps the last good file if the new one would shrink below half of it.
No keyed or credentialed URL is ever written (same public_url rule as the fallback).
"""
import importlib.util
import json
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from nfl import nfl_rank, display_name  # noqa: E402

_spec = importlib.util.spec_from_file_location("fallback", HERE / "build-fallback-m3u.py")
fallback = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fallback)

SOURCES = [
    "sports-fallback.m3u",
    "https://iptv-org.github.io/iptv/categories/sports.m3u",
    "https://iptv-org.github.io/iptv/countries/us.m3u",
    "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/samsungtvplus_us.m3u",
    "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/plutotv_us.m3u",
    "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/plex_us.m3u",
    "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/tubi_all.m3u",
]
MAX_PER_NAME = 2  # a second copy is failover; more is clutter
OUT = Path("nfl.m3u")


def load(src):
    if src.startswith("http"):
        return fallback.fetch(src)
    return Path(src).read_text(encoding="utf-8")


def streams(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "VLC/3.0.18"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            head = resp.read(4096).decode("utf-8", "replace")
            return resp.status == 200 and ("#EXTM3U" in head or "#EXT-X" in head)
    except Exception:  # noqa: BLE001 - a dead stream is just not kept
        return False


def set_group(extinf, group):
    if 'group-title="' in extinf:
        return re.sub(r'group-title="[^"]*"', f'group-title="{group}"', extinf, count=1)
    head, _, name = extinf.partition(",")
    return f'{head} group-title="{group}",{name}'


def main():
    candidates, seen = [], set()
    for src in SOURCES:
        try:
            entries = fallback.parse_m3u(load(src))
        except Exception:  # noqa: BLE001
            print("[warn] a source was unavailable", file=sys.stderr)
            continue
        for extinf, directives, url in entries:
            rank = nfl_rank(display_name(extinf))
            if rank is None or url in seen or not fallback.public_entry((extinf, directives, url)):
                continue
            seen.add(url)
            candidates.append((rank, display_name(extinf), extinf, directives, url))

    with ThreadPoolExecutor(8) as pool:
        alive = list(pool.map(lambda c: streams(c[4]), candidates))
    live = sorted((c for c, ok in zip(candidates, alive) if ok), key=lambda c: (c[0], c[1].lower()))

    kept, per_name = [], {}
    for rank, name, extinf, directives, url in live:
        key = re.sub(r"\s*\(.*?\)", "", name).lower()
        if per_name.get(key, 0) >= MAX_PER_NAME:
            continue
        per_name[key] = per_name.get(key, 0) + 1
        kept.append((set_group(extinf, "NFL"), directives, url))

    previous = OUT.read_text(encoding="utf-8").count("#EXTINF") if OUT.exists() else 0
    print(f"[nfl] {len(candidates)} candidates, {len(live)} streaming, {len(kept)} kept (previous {previous})")
    if not kept or (previous >= 10 and len(kept) * 2 < previous):
        print("[warn] NFL list shrank sharply; keeping the last good nfl.m3u", file=sys.stderr)
        return 0

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    out = ["#EXTM3U", f"# Generated {now}: NFL-capable public channels that were streaming at build time.",
           "# National carriers first (NFL Network, ESPN, ESPN2, FS1, FOX Deportes), then local FOX/CBS/NBC/ABC.",
           "# Local stations' web streams can black out network games."]
    for extinf, directives, url in kept:
        out.append(extinf)
        out.extend(directives)
        out.append(url)
    fallback.write_atomic(str(OUT), "\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
