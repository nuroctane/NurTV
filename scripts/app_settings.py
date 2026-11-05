"""Android backups of private app state, filtered for likely sign-in data.

    python scripts/app_settings.py sanitize <in.ab> <out.ab>   keep state, drop sign-ins
    python scripts/app_settings.py list <file.ab>              show what an .ab holds

SmartTube (SponsorBlock, shorts, player presets), S0undTV (Luminous proxy
slots), CloudStream (repos + downloaded .cs3 plugins), Zangetsu (provider repos
+ installed providers) and Watchbox (repo list) all allow Android backup, so
`adb backup` / `adb restore` can move that state between TVs of the same model.

A raw backup also holds account sessions. `sanitize` drops caches, webview
cookies and storage, no-backup data, any file whose name looks like a
credential store, and every shared_prefs key that looks like a credential.
Everything dropped is printed so it can be checked. Filtering is heuristic and
cannot guarantee the resulting archive contains no sensitive data.
"""
import io
import re
import sys
import tarfile
import xml.etree.ElementTree as ET
import zlib

HEADER = b"ANDROID BACKUP\n"
# Key or file names that carry an identity rather than a preference.
SECRET = re.compile(
    r"token|auth|cookie|session|passw|refresh|account|oauth|credential|e-?mail"
    r"|user_?id|login|signin|sign_in|secret|api_?key|visitor|device_?id|uuid"
    r"|secure|keystore|debrid|anilist|simkl|trakt|supabase|(?<![a-z])mal_",
    re.I,
)
# Backup domains (apps/<pkg>/<domain>/...) never worth moving.
SKIP_DOMAINS = {"c", "nb", "ef", "obb", "k"}  # cache, no_backup, external, obb, key-value
# Plugin and provider code is named after its site, not after what it stores.
CODE = (".js", ".cs3", ".jar", ".apk", ".dex")


def read_ab(path):
    data = open(path, "rb").read()
    if not data.startswith(HEADER):
        sys.exit(f"{path}: not an Android backup")
    lines = data.split(b"\n", 4)
    version, compressed, encryption = lines[1], lines[2], lines[3]
    if encryption != b"none":
        sys.exit(f"{path}: encrypted backup; take it again without a password")
    body = lines[4]
    if compressed == b"1":
        body = zlib.decompress(body)
    return version, body


def write_ab(path, version, tar_bytes):
    with open(path, "wb") as f:
        f.write(HEADER + version + b"\n1\nnone\n")
        f.write(zlib.compress(tar_bytes, 9))


def scrub_prefs(raw, label, dropped):
    root = ET.fromstring(raw)
    for el in list(root):
        name = el.get("name", "")
        if SECRET.search(name):
            root.remove(el)
            dropped.append(f"{label}: key {name}")
    return root, b"<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n" + ET.tostring(root, encoding="utf-8")


def sanitize(src, dst):
    version, body = read_ab(src)
    kept, dropped = [], []
    out = io.BytesIO()
    # Android backup archives can contain paths too long for USTAR; preserve
    # them with POSIX extended headers instead of failing mid-capture.
    with tarfile.open(fileobj=io.BytesIO(body)) as tin, tarfile.open(fileobj=out, mode="w", format=tarfile.PAX_FORMAT) as tout:
        for m in tin:
            parts = m.name.split("/")
            # apps/<pkg>/_manifest must stay first for its package; tin order is preserved.
            if len(parts) == 3 and parts[2] == "_manifest":
                tout.addfile(m, tin.extractfile(m))
                kept.append(m.name)
                continue
            if not m.isfile() or len(parts) < 4:
                continue
            domain, rest = parts[2], "/".join(parts[3:])
            base = parts[-1]
            if domain in SKIP_DOMAINS or "webview" in rest.lower() or "cache" in rest.lower():
                dropped.append(m.name)
                continue
            if SECRET.search(base) and not base.lower().endswith(CODE):
                dropped.append(f"{m.name} (credential-looking name)")
                continue
            if domain == "sp" and base.endswith(".xml"):
                root, xml = scrub_prefs(tin.extractfile(m).read(), m.name, dropped)
                m.size = len(xml)
                tout.addfile(m, io.BytesIO(xml))
                kept.append(f"{m.name} ({len(root)} keys)")
                continue
            tout.addfile(m, tin.extractfile(m))
            kept.append(f"{m.name} ({m.size} bytes)")
    write_ab(dst, version, out.getvalue())
    for k in kept:
        print(f"   keep  {k}")
    for d in dropped:
        print(f"   drop  {d}")
    for pkg in sorted({k.split("/")[1] for k in kept}):
        if not any(k.startswith(f"apps/{pkg}/") and "/_manifest" not in k for k in kept):
            print(f"   ! {pkg}: nothing but its manifest survived")


def list_ab(path):
    _, body = read_ab(path)
    with tarfile.open(fileobj=io.BytesIO(body)) as t:
        for m in t:
            print(f"{m.size:>9}  {m.name}")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "sanitize":
        sanitize(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "list":
        list_ab(sys.argv[2])
    else:
        sys.exit(__doc__)
