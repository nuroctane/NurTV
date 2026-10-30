"""Compare and merge the launcher's home.conf.

The TV's launcher rewrites its own copy: it keeps its header, drops any other
comments and reorders nothing. The repo's copy is the same keys plus the notes
that explain this household, so the two must never be compared byte-for-byte.

  python scripts/home_conf.py diff  <a> <b>      differing keys; exit 1 if any
  python scripts/home_conf.py merge <repo> <dev> device values into the repo file,
                                                 keeping the repo's comments/order

Keys the device no longer has keep the repo's value: the launcher documents that
unknown keys are preserved, so nothing is lost either way.
"""
import sys


def parse(path):
    values, order = {}, []
    try:
        text = open(path, encoding='utf-8').read()
    except FileNotFoundError:
        return values, order
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        if key not in values:
            order.append(key)
        values[key] = value
    return values, order


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ('diff', 'merge'):
        print(__doc__, file=sys.stderr)
        return 2
    mode, first, second = sys.argv[1:4]

    if mode == 'diff':
        a, _ = parse(first)
        b, _ = parse(second)
        diffs = 0
        for key in sorted(set(a) | set(b)):
            if a.get(key) != b.get(key):
                diffs += 1
                print(f"  {key}: {a.get(key, '(absent)')} -> {b.get(key, '(absent)')}")
        if diffs:
            print(f"  {diffs} key(s) differ")
            return 1
        return 0

    dev, dev_order = parse(second)
    repo_values, _ = parse(first)
    try:
        source = open(first, encoding='utf-8').read().splitlines()
    except FileNotFoundError:
        source = []

    out, used = [], set()
    for line in source:
        stripped = line.strip()
        if not stripped or stripped.startswith('#') or '=' not in line:
            out.append(line)
            continue
        key = line.split('=', 1)[0].strip()
        if key in dev:
            out.append(f'{key}={dev[key]}')
            used.add(key)
        else:
            out.append(line)          # the launcher dropped it; keep the repo's value
    extra = [k for k in dev_order if k not in used and k not in repo_values]
    if extra:
        out.append('# added on the TV, not in the repo before')
        out.extend(f'{k}={dev[k]}' for k in extra)

    with open(first, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out).rstrip('\n') + '\n')
    print(f"  merged {len(used)} value(s) from the device"
          + (f", {len(extra)} new key(s)" if extra else "")
          + ", repo comments kept")
    return 0


if __name__ == '__main__':
    sys.exit(main())
