#!/usr/bin/env python3
"""Print the manual media-source steps from the provision manifest."""
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "provision" / "sources.json"
with path.open(encoding="utf-8") as stream:
    sources = json.load(stream)

print("Manual media setup (installation and playback are not verified by this list):")
for entry in sources.get("manual", []):
    print(f"\n  {entry['app']} ({entry['package']})")
    print(f"    {entry['why']}")
    for url in ([entry['url']] if entry.get('url') else []) + entry.get('urls', []):
        print(f"    {url}")
    if entry.get("installed"):
        print("    Providers on source TV: " + ", ".join(entry["installed"]))
print("\n  Add sources in each app, confirm they are enabled, and test playback.")
print("  Check current third-party source availability and privacy before adding them.")
