"""Which channel names can carry an NFL game, and in what order to favour them.

Tier 0: national game carriers (NFL Network, RedZone, ESPN, ESPN2, FS1, FOX Deportes,
ESPN Deportes) plus the NFL Channel (FAST replays and shows, no live games).
Tier 1: local ABC/CBS/FOX/NBC stations by call sign (Sunday and prime-time games,
when the station's own stream carries the network feed).
Anything else, including network news/weather channels, is not an NFL source.
"""
import re

_NATIONAL = [
    ("nfl network", re.compile(r"^NFL Network\b", re.I)),
    ("nfl redzone", re.compile(r"^NFL Red ?Zone\b", re.I)),
    ("espn", re.compile(r"^ESPN(?: HD)?(?:\s*\(.*\))?$", re.I)),
    ("espn2", re.compile(r"^ESPN\s?2(?: HD)?(?:\s*\(.*\))?$", re.I)),
    ("fs1", re.compile(r"^(?:FOX Sports 1|FS1)\b", re.I)),
    ("fox deportes", re.compile(r"^FOX Deportes\b", re.I)),
    ("espn deportes", re.compile(r"^ESPN Deportes\b", re.I)),
    ("nfl channel", re.compile(r"^NFL Channel\b", re.I)),
]
_LOCAL = re.compile(r"^(ABC|CBS|FOX|NBC)\s+(?:\d+\s+\w+|(?-i:[KW][A-Z]{2,4})\b)", re.I)
_NOT = re.compile(r"news|weather|soul|livenow|golazo|\bHQ\b|20/20|local|geo-?block|"
                  r"not 24/7|radio|ESPNU|latin|brazil|colombia|mexico|argentina|chile|"
                  r"netherlands|caribbean|africa|premium|\b[2-9]\s*\(", re.I)


def nfl_rank(name):
    """(tier, order) for an NFL-capable channel name, or None if it is not one."""
    name = (name or "").strip()
    if not name or _NOT.search(name):
        return None
    for order, (_, pattern) in enumerate(_NATIONAL):
        if pattern.search(name):
            return (0, order)
    m = _LOCAL.search(name)
    if m:
        return (1, ["FOX", "CBS", "NBC", "ABC"].index(m.group(1).upper()))
    return None


def display_name(extinf):
    return extinf.split(",", 1)[1].strip() if "," in extinf else ""
