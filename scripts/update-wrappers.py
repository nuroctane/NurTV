"""Install verified local wrappers with APK backups and byte-for-byte readback.

Usage: python scripts/update-wrappers.py --serial <tv-ip>:5555 [--slug framextv]
Never uninstalls an app to bypass a signing error. Does not launch or reboot TV.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_files():
    base = ROOT / 'apps/webwrap'
    return sorted([*base.joinpath('src').rglob('*.java'), base / 'manifest.template.xml',
                   base / 'build.sh', base / 'apps.txt'])


def source_digest():
    h = hashlib.sha256()
    for path in source_files():
        h.update(path.relative_to(ROOT / 'apps/webwrap').as_posix().encode())
        h.update(path.read_bytes())
    return h.hexdigest()


def configured_apps():
    """slug -> applicationId, straight from apps.txt (the build's own list)."""
    apps = {}
    for line in (ROOT / 'apps/webwrap/apps.txt').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        slug, package = line.split('|')[:2]
        apps[slug.strip()] = package.strip()
    return apps


def main():
    apps = configured_apps()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--slug', choices=sorted(apps))
    parser.add_argument('--adb', default=os.environ.get('ADB'))
    args = parser.parse_args()
    sdk_adb = Path.home() / 'AppData/Local/Android/Sdk/platform-tools/adb.exe'
    adb = args.adb or (str(sdk_adb) if sdk_adb.exists() else shutil.which('adb'))
    if not adb:
        parser.error('adb not found')

    def run(*command, check=True):
        proc = subprocess.run([adb, '-s', args.serial, *command], check=check,
                              capture_output=True, text=True, timeout=90)
        return proc.stdout.strip()

    def installed_path(package):
        """Remote path of the installed base APK, or None on a first install."""
        # `pm path` exits 1 for an absent package; that is the first-install case,
        # not a failure.
        paths = run('shell', 'pm', 'path', package, check=False).splitlines()
        if not paths:
            return None
        if len(paths) != 1 or not paths[0].startswith('package:'):
            raise RuntimeError(f'{package}: expected one installed base APK; refusing install')
        return paths[0].removeprefix('package:').strip()

    if run('get-state') != 'device':
        raise RuntimeError('TV not authorized')
    manifests = sorted((ROOT / 'apps/webwrap/out').glob('*.json'))
    if args.slug:
        manifests = [ROOT / f'apps/webwrap/out/{args.slug}-tv.json']
    if not manifests:
        raise RuntimeError('build wrappers first')
    plans = []
    for receipt in manifests:
        data = json.loads(receipt.read_text())
        apk = receipt.with_suffix('.apk')
        slug = receipt.name.removesuffix('-tv.json')
        if data['package'] != apps.get(slug):
            raise RuntimeError(f"{receipt.name}: package {data['package']!r} is not {slug}'s in apps.txt")
        if digest(apk) != data['apk_sha256']:
            raise RuntimeError(f'{apk.name}: artifact differs from build receipt')
        if source_digest() != data['source_sha256']:
            raise RuntimeError(f'{apk.name}: source changed since build; rebuild first')
        plans.append((data, apk, installed_path(data['package'])))
    backup = ROOT / 'backups' / ('wrappers-' + datetime.now().strftime('%Y-%m-%d_%H%M%S'))
    backup.mkdir(parents=True)
    with zipfile.ZipFile(backup / 'new-wrapper-source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in [*source_files(), *(ROOT / 'apps/webwrap/tools').glob('*')]:
            if path.is_file():
                archive.write(path, path.relative_to(ROOT / 'apps/webwrap').as_posix())
    # Preserve ALL previous APKs before the first install.
    for data, apk, remote in plans:
        if remote is None:            # first install: there is nothing to preserve
            data['previous_apk_sha256'] = None
            (backup / apk.with_suffix('.json').name).write_text(json.dumps(data, indent=2) + '\n')
            continue
        old = backup / apk.name
        run('pull', remote, str(old))
        data['previous_apk_sha256'] = digest(old)
        (backup / apk.with_suffix('.json').name).write_text(json.dumps(data, indent=2) + '\n')
    for data, apk, _ in plans:
        result = run('install', '-r', str(apk))
        if 'Success' not in result:
            raise RuntimeError(f"{data['package']}: install failed; old APK retained at {backup}")
        readback = backup / ('installed-' + apk.name)
        run('pull', installed_path(data['package']), str(readback))
        if digest(readback) != data['apk_sha256']:
            raise RuntimeError(f"{data['package']}: installed APK differs from build")
        version = run('shell', 'dumpsys', 'package', data['package'])
        if f"versionCode={data['versionCode']} " not in version:
            raise RuntimeError(f"{data['package']}: version check failed")
        print(f"verified {data['package']} v{data['version']} sha256={data['apk_sha256']}")
    print(f'Previous APKs and receipts: {backup}')


if __name__ == '__main__':
    main()
