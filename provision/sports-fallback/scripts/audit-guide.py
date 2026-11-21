#!/usr/bin/env python3
"""Compare playlist tvg-ids with local XMLTV guide files, without fuzzy guesses."""
import argparse
import gzip
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


def read_ids(path):
    found = []
    for line in Path(path).read_text(encoding='utf-8-sig', errors='replace').splitlines():
        if line.startswith('#EXTINF'):
            match = re.search(r'\btvg-id="([^"]+)"', line)
            found.append(match.group(1).strip() if match else '')
    return found


def read_guide(path, now):
    channels, upcoming = set(), Counter()
    opener = gzip.open if str(path).lower().endswith('.gz') else open
    with opener(path, 'rb') as stream:
        for _, element in ET.iterparse(stream, events=('end',)):
            if element.tag == 'channel':
                channels.add(element.get('id', ''))
                element.clear()
            elif element.tag == 'programme':
                value = element.get('stop', '')
                try:
                    # XMLTV timestamps without an offset are ambiguous; do not
                    # report them as current coverage.
                    if not re.fullmatch(r'\d{14} [+-]\d{4}', value):
                        raise ValueError('missing offset')
                    stop = datetime.strptime(value, '%Y%m%d%H%M%S %z')
                    if stop > now:
                        upcoming[element.get('channel', '')] += 1
                except ValueError:
                    pass
                element.clear()
    return channels, upcoming


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('playlist')
    parser.add_argument('guides', nargs='+', help='local XMLTV .xml or .xml.gz files')
    args = parser.parse_args()
    now = datetime.now(timezone.utc)
    ids = read_ids(args.playlist)
    channels, upcoming = set(), Counter()
    try:
        for guide in args.guides:
            found, count = read_guide(guide, now)
            channels.update(found)
            upcoming.update(count)
    except (OSError, ET.ParseError) as exc:
        print(f'Could not read XMLTV guide: {exc}', file=sys.stderr)
        return 1
    matched = sum(bool(item) and item in channels for item in ids)
    covered = sum(bool(item) and upcoming[item] > 0 for item in ids)
    print(json.dumps({'entries': len(ids), 'missing_tvg_id': sum(not x for x in ids),
                      'matched_exact_id': matched, 'with_current_or_future_programmes': covered,
                      'unmatched_ids': sorted(set(x for x in ids if x and x not in channels)),
                      'checked_utc': now.isoformat()}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
