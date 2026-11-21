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

Every source must have a valid current or cached copy before publishing. A
partial first run leaves the previous output intact; later failures reuse the
last good source snapshot and are reported as degraded.
"""
import json
import re
import sys
import os
import tempfile
import urllib.request
from datetime import datetime, timezone
from urllib.parse import urlsplit, parse_qsl
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from nfl import nfl_rank, display_name  # noqa: E402

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
    """Return (metadata, directives, URL), preserving per-stream directives."""
    entries = []
    lines = [ln.strip().lstrip('\ufeff') for ln in text.splitlines()]
    if not lines or not re.match(r'^#EXTM3U(?:\s|$)', lines[0]):
        raise ValueError('not an extended M3U playlist')
    i = 0
    while i < len(lines):
        if lines[i].startswith("#EXTINF"):
            extinf = lines[i]
            j = i + 1
            directives = []
            while j < len(lines) and (not lines[j] or lines[j].startswith("#")):
                if lines[j].startswith('#EXTINF'):
                    break
                if lines[j]:
                    directives.append(lines[j])
                j += 1
            if j < len(lines) and not lines[j].startswith('#'):
                entries.append((extinf, directives, lines[j]))
                i = j + 1
                continue
        i += 1
    return entries


def public_url(url):
    """Reject URLs containing obvious credentials before writing public files."""
    parsed = urlsplit(url)
    if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password:
        return False
    forbidden = {'key', 'api_key', 'apikey', 'token', 'access_token', 'auth', 'authorization', 'password', 'secret'}
    return not any(k.lower() in forbidden for k, _ in parse_qsl(parsed.query, keep_blank_values=True))


def public_entry(entry):
    metadata, directives, url = entry
    # Headers and metadata are published too; do not expose obvious secrets.
    if re.search(r'(?i)(?:authorization\s*[:=]|(?:access[_-]?token|api[_-]?key|password|secret|[?&]key)\s*=)',
                 '\n'.join([metadata, *directives])):
        return False
    return public_url(url)


def write_atomic(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


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
    merged = []
    seen_urls = set()
    stats = {"generated_utc": now.isoformat(), "sources": {}, "total": 0}
    cache_path = Path('source-cache.json')
    try:
        cache = json.loads(cache_path.read_text(encoding='utf-8')) if cache_path.exists() else {}
        if not isinstance(cache, dict):
            raise ValueError('cache must be an object')
    except (ValueError, OSError) as exc:
        print(f'[error] invalid source cache: {exc}', file=sys.stderr)
        return 1
    next_cache = dict(cache)
    incomplete = False

    for src in SOURCES:
        try:
            text = fetch(src["url"])
            entries = [entry for entry in parse_m3u(text)
                       if (not src['sports_only'] or is_sports(entry[0])) and public_entry(entry)]
            prior = cache.get(src['name'], {})
            prior_count = len(prior.get('entries', []))
            if not entries or (prior_count >= 10 and len(entries) * 2 < prior_count):
                raise ValueError(f'empty or unexpectedly small source ({len(entries)} vs {prior_count})')
            next_cache[src['name']] = {'updated_utc': now.isoformat(), 'entries': entries}
            status = 'ok'
        except Exception as exc:  # noqa: BLE001 - one bad source must not kill the run
            # Do not log URLs or exception text, which can contain credentials.
            entries = cache.get(src['name'], {}).get('entries', [])
            if not entries:
                print(f"[error] {src['name']}: unavailable and no cached copy; keeping current playlist", file=sys.stderr)
                incomplete = True
                continue
            print(f"[warn] {src['name']}: using last good cached copy", file=sys.stderr)
            status = 'cached'
        kept = 0
        for extinf, directives, url in entries:
            if not public_entry((extinf, directives, url)):
                incomplete = True
                continue
            if url in seen_urls:
                continue
            seen_urls.add(url)
            merged.append((extinf, directives, url))
            kept += 1
        stats['sources'][src['name']] = {'status': status, 'available': len(entries), 'kept': kept,
                                          'last_good_utc': next_cache[src['name']]['updated_utc']}
        print(f"[{status}] {src['name']}: {len(entries)} available, {kept} kept")

    # NFL carriers lead the playlist (national first, then local network stations);
    # everything else keeps its source order behind them.
    merged.sort(key=lambda e: nfl_rank(display_name(e[0])) or (9, 0))
    stats["nfl"] = sum(1 for e in merged if nfl_rank(display_name(e[0])))
    stats["total"] = len(merged)
    if incomplete or not merged:
        print("[error] incomplete sources; current published files left unchanged", file=sys.stderr)
        return 1

    out = ["#EXTM3U"]
    out.append(f"# Generated {now.strftime('%Y-%m-%d %H:%M UTC')} — Sports fallback M3U")
    out.append("# Primary is the VM rebeliptv aggregator; use this only if the VM is down.")
    out.append("# Open TV Atlas entries are unofficial restreams: they may carry live")
    out.append("# games but die mid-game. Tubi/Roku entries are FAST shoulder programming.")
    for extinf, directives, url in merged:
        out.append(extinf)
        out.extend(directives)
        out.append(url)
    write_atomic('source-cache.json', json.dumps(next_cache, indent=2) + '\n')
    write_atomic('sports-fallback.m3u', '\n'.join(out) + '\n')
    write_atomic('stats.json', json.dumps(stats, indent=2) + '\n')
    print(f"[done] {len(merged)} entries -> sports-fallback.m3u")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
