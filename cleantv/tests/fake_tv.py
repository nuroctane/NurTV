#!/usr/bin/env python3
"""A pretend Fire TV for the scripts: answers adb commands from a JSON state file
and logs every shell command, so tests can see exactly what a script would do.

Like a real TV on Wi-Fi, stopping the DNS filter's VPN breaks the adb session
until the host disconnects and connects again."""
import json
import os
import sys
from pathlib import Path

VPN_APP = 'dnsfilter.android'

args = sys.argv[1:]
state_path = Path(os.environ['FAKE_TV_STATE'])
state = json.loads(state_path.read_text())


def save():
    state_path.write_text(json.dumps(state))


if args == ['start-server'] or args[:1] == ['connect']:
    sys.exit(0)
if args[:1] == ['disconnect']:
    state['dropped'] = False
    save()
    sys.exit(0)
if args[-1:] == ['get-state']:
    print('device')
    sys.exit(0)
if len(args) < 3 or args[0] != '-s' or args[2] != 'shell':
    sys.exit(91)

command = ' '.join(args[3:])
if state.get('dropped'):
    print('error: closed')
    sys.exit(1)
with Path(os.environ['FAKE_TV_LOG']).open('a') as log:
    log.write(command + '\n')

apps = state['packages']
settings = state.setdefault('settings', {})
words = command.split()

if words[:1] == ['settings']:
    verb, rest = words[1], words[2:]
    if verb == 'put' and len(rest) == 3:
        settings[f'{rest[0]}/{rest[1]}'] = '' if rest[2] == '""' else rest[2]
        save()
    elif verb == 'put':
        state.setdefault('bad', []).append(command)
        save()
        print('Bad arguments')
    elif verb == 'get' and len(rest) == 2:
        print(settings.get(f'{rest[0]}/{rest[1]}', 'null'))
    elif verb == 'delete' and len(rest) == 2:
        settings.pop(f'{rest[0]}/{rest[1]}', None)
        save()
elif command == 'echo ok':
    print('ok')
elif command == 'cat /proc/sys/kernel/random/boot_id':
    print(f"boot-{state.get('boots', 0)}")
elif command == 'svc power reboot' and state.get('svc_refused'):
    print('Killed')
elif command == 'getprop sys.shutdown.requested':
    print(state.pop('shutting_down', ''))
    save()
elif command in ('svc power reboot', 'reboot'):
    if command == 'svc power reboot':
        state['shutting_down'] = '1reboot'
        save()
    if not state.get('ignores_reboot'):
        state['boots'] = state.get('boots', 0) + 1
        save()
elif command == 'getprop ro.build.version.sdk':
    print(state.get('sdk', 28))
elif command == 'getprop ro.product.manufacturer':
    print('Amazon')
elif command == 'getprop sys.boot_completed':
    print(1)
elif command == 'cmd package help':
    print('Package manager (package) commands:\n  path [--user USER_ID] PACKAGE')
elif words[:2] == ['pm', 'path']:
    if words[2] in apps:
        print(f'package:/system/app/{words[2]}.apk')
elif command == 'pm list packages -s':
    print('\n'.join(f'package:{p}' for p, a in apps.items() if a['system']))
elif command == 'pm list packages -d':
    print('\n'.join(f'package:{p}' for p, a in apps.items() if not a['enabled']))
elif words[:4] == ['pm', 'disable-user', '--user', '0']:
    name = words[4]
    if apps.get(name, {}).get('protected'):
        print('Security exception: Cannot disable a protected package')
    else:
        apps[name]['enabled'] = False
        if name == VPN_APP:
            state['dropped'] = True
        save()
        print(f'Package {name} new state: disabled-user')
elif words[:4] == ['pm', 'enable', '--user', '0']:
    if words[4] in apps:
        apps[words[4]]['enabled'] = True
        save()
        print(f'Package {words[4]} new state: enabled')
elif words[:4] == ['pm', 'uninstall', '--user', '0']:
    apps.pop(words[-1], None)
    save()
    print('Success')
elif words[:2] == ['dumpsys', 'package']:
    print('    userId=10050')
    if len(words) > 2 and words[2] in apps:
        a = apps[words[2]]
        print(f"    User 0: installed=true enabled={a.get('enabled_state', 1 if a['enabled'] else 3)} hidden=false")
elif len(words) == 5 and words[:1] == ['pm'] and words[2:4] == ['--user', '0'] and words[1] in ('default-state', 'disable', 'disable-until-used'):
    a = apps[words[4]]
    code = {'default-state': 0, 'disable': 2, 'disable-until-used': 4}[words[1]]
    a['enabled_state'] = code
    a['enabled'] = code == 0
    save()
    print(f'Package {words[4]} new state: {words[1]}')
elif command == 'ps -A -o NAME':
    print('NAME')
elif command == 'dumpsys activity activities':
    print('  mResumedActivity: ActivityRecord{1 u0 tv.cleantv.home/.Home t1}')
