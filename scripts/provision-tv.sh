#!/usr/bin/env bash
# Put this repo's captured setup onto another TV of the same model.
#
#   ./scripts/provision-tv.sh <tv-ip> [--dry-run] [--verify-only] [--skip-system] [--force]
#
#   --dry-run      say what would happen; touch nothing
#   --verify-only  change nothing, just check the TV against provision/golden-state.json
#   --skip-system  skip the CleanTV pass (debloat/lockdown/DNS filter/HOME takeover)
#   --force        provision even if the TV is a different model
#
# After the golden-state APKs, scripts/apply-sources.sh installs the Watchbox
# extension packages in provision/sources.json, then private/app-settings/app-settings.ab
# (from ./scripts/capture-app-settings.sh) can optionally restore settings and
# CloudStream/Zangetsu/Watchbox sources. Arvio/Lumera add-ons forbid backup: manual.
#
# Source of truth is provision/golden-state.json, captured from the working TV by
# ./scripts/capture-tv.sh. Nothing here ever uninstalls a package: a signing
# mismatch is reported, never worked around by deleting the installed app.
#
# Golden State is what was done to the TV, not what version its apps are.
# Third-party apps update all the time, so their versions are NOT tracked:
# a package is verified by presence only (check: presence), and the apk/sha256
# in the golden state are the install source used when the app is missing,
# hash-checked before install, never compared against the TV. The one exception
# is the CleanTV launcher (check: exact): it is this household's own build, its
# version IS the QoL work, and provision installs exactly that build.
# The `tweaks` section of the golden state records the actual work: plugins,
# add-ons, settings, DNS, ad blocking, video-player/browser-wrapper work,
# and launcher QoL (dim, circular nav, Guard).
#
# The new TV needs: ADB debugging on (Settings > My Fire TV > About > tap OK 7x >
# Developer Options) and the "Allow ADB debugging?" prompt accepted.
set -uo pipefail

# Git Bash rewrites Unix-looking arguments into Windows paths, which would turn
# /sdcard/... into C:/Program Files/Git/sdcard/... — so exclude the device prefixes.
# MSYS_NO_PATHCONV must NOT be set here: it also stops the conversion of this
# script's own temp paths, which native adb.exe/python then cannot open. Excluding
# the device prefixes is the precise fix; everything else converts normally.
unset MSYS_NO_PATHCONV
export MSYS2_ARG_CONV_EXCL="${MSYS2_ARG_CONV_EXCL:+$MSYS2_ARG_CONV_EXCL;}/sdcard;/data;/storage;/system"
source "$(dirname "${BASH_SOURCE[0]}")/_adb.sh"
require_adb || exit 1

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE=$ROOT/provision/golden-state.json
UPDATES=$ROOT/provision/apk-updates.json
IP=""; DRY=0; VERIFY_ONLY=0; SKIP_SYSTEM=0; FORCE=0; RESTORE_APP_SETTINGS=0
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    --verify-only) VERIFY_ONLY=1 ;;
    --skip-system) SKIP_SYSTEM=1 ;;
    --force) FORCE=1 ;;
    --restore-app-settings) RESTORE_APP_SETTINGS=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) IP=$a ;;
  esac
done
[ -n "$IP" ] || { echo "usage: $0 <tv-ip> [--dry-run] [--verify-only] [--skip-system] [--force]" >&2; exit 2; }
[ -f "$STATE" ] || { echo "no provision/golden-state.json — run ./scripts/capture-tv.sh <working-tv-ip> first" >&2; exit 1; }
S="$IP:5555"

step() { printf '\n== %s ==\n' "$*"; }
note() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
FAILED=0
fail() { warn "$*"; FAILED=1; }

sh_() { "$ADB_BIN" -s "$S" shell "$*" </dev/null 2>/dev/null | tr -d '\r'; }
sha() { sha256sum "$1" | awk '{print $1}'; }
rel() { printf '%s' "${1#"$ROOT"/}"; }
# Native python needs Windows paths, and Git Bash only converts them itself when the
# caller has not exported MSYS_NO_PATHCONV (device paths need that variable). Convert
# explicitly, so the script behaves the same either way.
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/nurtv-provision.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
# Packages whose installed APK the app layer already pulled and hashed. Nothing in
# the system pass replaces an app APK, so they are not downloaded twice.
: > "$WORK/verified.txt"

step "plan"
python - "$(win "$STATE")" "$(win "$WORK")" "$(win "$UPDATES")" <<'PY'
import json, sys
from pathlib import Path
state = json.load(open(sys.argv[1], encoding='utf-8'))
out = sys.argv[2]
updates_path = Path(sys.argv[3])
if updates_path.exists():
    updates = json.load(updates_path.open(encoding='utf-8')).get('packages', [])
    packages = {p['package']: p for p in state['packages']}
    seen = set()
    for update in updates:
        name = update['package']
        if name in seen or name not in packages:
            raise ValueError(f'duplicate or unknown update package: {name}')
        seen.add(name)
        target = packages[name]
        # The no-downgrade check only applies where the golden state pins a
        # version at all (the CleanTV launcher). Third-party apps carry no
        # version in the golden state, so an override just replaces the
        # install source: apk + sha256 (+ version fields when supplied).
        if target.get('versionCode') is not None and 'versionCode' in update:
            if int(update['versionCode']) < int(target['versionCode']):
                raise ValueError(f'update would downgrade {name}')
        target.update(install='install', apk=[update['apk']], sha256=[update['sha256']])
        if 'versionCode' in update:
            target['versionCode'] = int(update['versionCode'])
        if 'versionName' in update:
            target['versionName'] = update['versionName']
with open(f'{out}/meta.sh', 'w', encoding='utf-8', newline='\n') as f:
    f.write(f"GUARD_DEVICE={state['guard']['ro.product.device']!r}\n")
    f.write(f"GUARD_MODEL={state['guard']['ro.product.model']!r}\n")
    f.write(f"GUARD_SDK={state['guard']['ro.build.version.sdk']!r}\n")
    f.write(f"CAPTURED_AT={state['captured_at']!r}\n")
    f.write(f"HOME_CONF={state['config']['home_conf']!r}\n")
    f.write(f"ART_DIR={state['config']['art']!r}\n")
    f.write(f"WALLPAPER={state['config']['wallpaper']!r}\n")
    f.write(f"CLEANTV_CONF={state['config']['cleantv_conf']!r}\n")
with open(f'{out}/packages.tsv', 'w', encoding='utf-8', newline='\n') as f:
    # versionCode is LAST on purpose: bash `read` with a tab IFS collapses
    # empty fields in the middle, so a version-less (presence) row would
    # shift every later column left. A trailing empty field is simply unset.
    for p in state['packages']:
        f.write('\t'.join([p['package'], p['install'],
                           p['role'], ','.join(p['apk']), ','.join(p['sha256']),
                           p.get('check', 'presence'),
                           str(p.get('versionCode') or '')]) + '\n')
with open(f'{out}/settings.tsv', 'w', encoding='utf-8', newline='\n') as f:
    for k, v in state['settings'].items():
        f.write(f'{k}\t{v if v is not None else ""}\n')
with open(f'{out}/disabled.txt', 'w', encoding='utf-8', newline='\n') as f:
    for p in state['disabled_packages']:
        f.write(p + '\n')
PY
[ -f "$WORK/meta.sh" ] || { echo "could not read $STATE — is it valid JSON?" >&2; exit 1; }
# shellcheck disable=SC1091
source "$WORK/meta.sh"
note "from      provision/golden-state.json, captured $CAPTURED_AT"
[ -f "$UPDATES" ] && note "updates   provision/apk-updates.json overrides the install source for a package"
note "target    $S"
note "expected  $GUARD_DEVICE / $GUARD_MODEL, sdk $GUARD_SDK"
note "packages  $(wc -l < "$WORK/packages.tsv" | tr -d ' ') "
[ "$DRY" = 1 ] && note "DRY RUN — nothing will be written"

step "connect"
"$ADB_BIN" connect "$S" >/dev/null 2>&1
if [ "$("$ADB_BIN" -s "$S" get-state 2>/dev/null)" != device ]; then
  echo "no adb to $S — run ./scripts/connect.sh $IP, and accept the prompt on the TV" >&2
  exit 1
fi
MODEL=$(sh_ "getprop ro.product.model"); DEVICE=$(sh_ "getprop ro.product.device")
SDK=$(sh_ "getprop ro.build.version.sdk"); FIREOS=$(sh_ "getprop ro.build.version.name")
note "found     $DEVICE / $MODEL  Fire OS $FIREOS (sdk $SDK)"

# The profile is model-specific (input ids, debloat list), so a mismatch is a stop.
if [ "$DEVICE" != "$GUARD_DEVICE" ] || [ "$SDK" != "$GUARD_SDK" ] || [ "$MODEL" != "$GUARD_MODEL" ]; then
  if [ "$FORCE" = 1 ]; then
    warn "different TV ($DEVICE / $MODEL, sdk $SDK) — continuing because of --force"
  else
    echo >&2
    echo "refusing: this profile was captured on $GUARD_DEVICE / $GUARD_MODEL (sdk $GUARD_SDK)" >&2
    echo "and this TV is $DEVICE / $MODEL (sdk $SDK). Input ids and the debloat list are" >&2
    echo "model-specific. Use a TV of the same model, or pass --force if you are sure." >&2
    exit 1
  fi
fi

have() { sh_ "pm list packages | grep -c '^package:$1\$'" | head -1; }
vcode() { sh_ "dumpsys package $1" | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1; }
front_activity() { sh_ "dumpsys activity activities" | sed -n 's/.* u0 \([^ ]*\)\/.*/\1/p' | head -1; }

if [ "$VERIFY_ONLY" = 0 ] && [ "$DRY" = 0 ]; then
  step "backup of the target TV"
  "$ROOT/scripts/backup-packages.sh" "$IP" | sed 's/^/   /'
fi

step "app layer"
while IFS=$'\t' read -r pkg mode role apks hashes check code; do
  [ -n "$pkg" ] || continue
  [ -n "$check" ] || check=presence
  IFS=',' read -r -a files <<<"$apks"
  IFS=',' read -r -a sums <<<"$hashes"
  valid=1
  for i in "${!files[@]}"; do
    if [ ! -f "$ROOT/${files[$i]}" ]; then
      fail "$pkg: ${files[$i]} is missing from the repo"
      valid=0
      continue
    fi
    if [ "$(sha "$ROOT/${files[$i]}")" != "${sums[$i]}" ]; then
      fail "$pkg: ${files[$i]} does not match its recorded sha256 (rebuild/re-capture)"
      valid=0
    fi
  done
  [ "$valid" = 1 ] || continue
  local_code=$(vcode "$pkg")
  if [ "$check" = presence ]; then
    # Golden State does not pin this app's version: installed at any version
    # is good. The repo APK is only the install source when it is missing.
    if [ -n "$local_code" ]; then
      note "present   $pkg  code=$local_code (version not pinned)"
      echo "$pkg" >> "$WORK/verified.txt"
      continue
    fi
    if [ "$VERIFY_ONLY" = 1 ]; then
      fail "$pkg: not installed"
      continue
    fi
    if [ "$DRY" = 1 ]; then
      note "install   $pkg  from ${files[0]} (not installed)"
      continue
    fi
  else
    # check=exact (the CleanTV launcher only): current when the version
    # matches and the installed base APK is byte-identical.
    if [ -n "$local_code" ] && [ "$local_code" = "$code" ] && [ "${#files[@]}" = 1 ]; then
      remote=$(sh_ "pm path $pkg" | sed 's/^package://' | head -1)
      "$ADB_BIN" -s "$S" pull "$remote" "$WORK/check.apk" >/dev/null 2>&1
      if [ "$(sha "$WORK/check.apk")" = "${sums[0]}" ]; then
        note "current   $pkg  code=$code"
        echo "$pkg" >> "$WORK/verified.txt"
        continue
      fi
      note "reinstall $pkg  (code=$code but the APK differs)"
    fi
    if [ "$VERIFY_ONLY" = 1 ]; then
      fail "$pkg: not at $code on $S (has ${local_code:-none})"
      continue
    fi
    if [ "$DRY" = 1 ]; then
      note "install   $pkg  code=$code  from ${files[0]}"
      continue
    fi
  fi
  args=(); for f in "${files[@]}"; do args+=("$ROOT/$f"); done
  out=$("$ADB_BIN" -s "$S" "$mode" -r "${args[@]}" 2>&1 | grep -m1 -E 'Success|Failure|failed' || true)
  case $out in
    *Success*) ;;
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
      fail "$pkg: signed with a different key than the one installed — uninstall it on the TV by hand, then re-run (never done automatically)"
      continue ;;
    *) fail "$pkg: install failed: ${out:-no output}"; continue ;;
  esac
  new=$(vcode "$pkg")
  if [ "$check" = exact ]; then
    [ "$new" = "$code" ] || fail "$pkg: installed versionCode $new, expected $code"
  else
    [ -n "$new" ] || fail "$pkg: install reported success but the package is not on the TV"
  fi
  remote=$(sh_ "pm path $pkg" | sed 's/^package://' | head -1)
  "$ADB_BIN" -s "$S" pull "$remote" "$WORK/check.apk" >/dev/null 2>&1
  if [ "$(sha "$WORK/check.apk")" = "${sums[0]}" ]; then
    note "installed $pkg  code=$new  sha256 verified"
    echo "$pkg" >> "$WORK/verified.txt"
  else
    fail "$pkg: installed APK does not match the recorded sha256"
  fi
done < "$WORK/packages.tsv"

if [ "$SKIP_SYSTEM" = 0 ] && [ "$VERIFY_ONLY" = 0 ]; then
  step "system layer (CleanTV: debloat, lockdown, DNS filter, HOME takeover)"
  note "two reboots happen in here, ~5 minutes"
  if [ "$DRY" = 1 ]; then
    note "[dry-run] (cd cleantv && ./scripts/all.sh -y)   with ADB=$ADB_BIN ADB_SERIAL=$S"
  else
    conf=${CLEANTV_CONF:-cleantv/cleantv.conf}
    [ -f "$ROOT/$conf" ] || warn "$conf is missing — CleanTV will ask questions; copy it from the working TV's repo"
    if ( cd "$ROOT/cleantv" && ADB="$ADB_BIN" ADB_SERIAL="$S" ./scripts/all.sh -y ); then
      note "CleanTV pass finished"
    else
      fail "CleanTV pass failed — see its output above; the TV may need a manual HOME press"
    fi
    "$ADB_BIN" connect "$S" >/dev/null 2>&1
  fi
elif [ "$SKIP_SYSTEM" = 0 ]; then
  step "system layer"
  note "skipped with --verify-only"
fi

# Packages this household disabled beyond what CleanTV's scripts do. Applied here
# so a capture from the working TV is reproduced exactly; nothing is re-enabled
# that the golden state does not also have enabled.
if [ "$SKIP_SYSTEM" = 0 ] && [ "$VERIFY_ONLY" = 0 ] && [ "$DRY" = 0 ]; then
  step "extra debloat from the golden state"
  sh_ "pm list packages -d" | sed 's/^package://' | sort > "$WORK/target-disabled.txt"
  extra=0
  while read -r p; do
    [ -n "$p" ] || continue
    if ! grep -qx "$p" "$WORK/target-disabled.txt"; then
      if [ "$(have "$p")" = 1 ]; then
        sh_ "pm disable-user --user 0 $p" >/dev/null 2>&1
        note "disabled   $p"
        extra=$((extra+1))
      fi
    fi
  done < "$WORK/disabled.txt"
  [ "$extra" = 0 ] && note "nothing extra to disable"
fi

if [ "$VERIFY_ONLY" = 0 ]; then
  step "launcher config + assets"
  HD=/sdcard/Android/data/tv.cleantv.home/files
  if [ "$DRY" = 1 ]; then
    note "[dry-run] push $([ -n "$HOME_CONF" ] && echo "$HOME_CONF") -> $HD/home.conf"
    note "[dry-run] push $ART_DIR/*.png -> $HD/art/"
    note "[dry-run] push $WALLPAPER -> $HD/wallpaper.jpg"
  elif [ "$(have tv.cleantv.home)" != 1 ]; then
    warn "tv.cleantv.home is not installed — config not pushed"
  else
    # The app creates its own files dir; make sure of it before pushing into it.
    sh_ "mkdir -p $HD/art" >/dev/null 2>&1
    "$ADB_BIN" -s "$S" push "$ROOT/$HOME_CONF" "$HD/home.conf" >/dev/null 2>&1 \
      && note "pushed     $HOME_CONF -> home.conf" || fail "could not push $HOME_CONF"
    for f in "$ROOT/$ART_DIR"/*.png; do
      [ -f "$f" ] || continue
      "$ADB_BIN" -s "$S" push "$f" "$HD/art/$(basename "$f")" >/dev/null 2>&1 \
        && note "pushed     art/$(basename "$f")" || fail "could not push $(basename "$f")"
    done
    [ -f "$ROOT/$WALLPAPER" ] && "$ADB_BIN" -s "$S" push "$ROOT/$WALLPAPER" "$HD/wallpaper.jpg" >/dev/null 2>&1 \
      && note "pushed     $WALLPAPER -> wallpaper.jpg" || true

    # Art is cached per tile, so the launcher has to restart for it to be read.
    # force-stop also drops the accessibility Guard: rebind it right after.
    step "launcher restart + Guard rebind"
    sh_ "am force-stop tv.cleantv.home" >/dev/null 2>&1
    sh_ "am start -n tv.cleantv.home/.Home" >/dev/null 2>&1
    sleep 3
    sh_ "settings put secure enabled_accessibility_services ''" >/dev/null 2>&1
    sleep 1
    sh_ "settings put secure enabled_accessibility_services tv.cleantv.home/tv.cleantv.home.Guard" >/dev/null 2>&1
    sh_ "settings put secure accessibility_enabled 1" >/dev/null 2>&1
    sleep 2
    note "guard: $(sh_ "settings get secure enabled_accessibility_services")"
  fi
fi

step "media sources"
src_args=("$IP")
[ "$DRY" = 1 ] && src_args+=(--dry-run)
[ "$VERIFY_ONLY" = 1 ] && src_args+=(--verify-only)
if "$ROOT/scripts/apply-sources.sh" "${src_args[@]}"; then
  if [ "$DRY" = 1 ]; then note "extension package plan complete"
  else note "extension packages match provision/sources.json"; fi
else
  fail "Watchbox extension packages are missing or the wrong build — see above"
fi

# App state in private data (SmartTube/S0undTV ad-blocking settings, CloudStream
# plugins, Zangetsu providers, Watchbox repo), filtered for likely sign-ins: the backup made by
# scripts/capture-app-settings.sh. adb restore needs one button press on the TV.
step "app state (SmartTube, S0undTV, CloudStream, Zangetsu, Watchbox)"
APPSET=$ROOT/private/app-settings/app-settings.ab
if [ "$RESTORE_APP_SETTINGS" = 0 ]; then
  note "skipped; use --restore-app-settings only on the intended target after reviewing the backup"
elif [ ! -f "$APPSET" ]; then
  note "no private/app-settings/app-settings.ab — run ./scripts/capture-app-settings.sh <working-tv-ip> once"
elif [ "$(sha "$APPSET")" != "$(cat "$APPSET.sha256" 2>/dev/null)" ]; then
  fail "private/app-settings/app-settings.ab does not match its .sha256; capture it again"
elif [ "$DRY" = 1 ] || [ "$VERIFY_ONLY" = 1 ]; then
  note "would restore $(rel "$APPSET") (one 'Restore my data' press on the TV)"
else
  note "On the TV: press 'Restore my data' (no password). Waiting up to 2 minutes."
  if timeout 150 "$ADB_BIN" -s "$S" restore "$(win "$APPSET")" </dev/null >/dev/null 2>&1; then
    note "restore command finished; check each app's settings and add-ons on the target TV"
  else
    fail "adb restore timed out or failed; rerun or press Restore on the TV"
  fi
fi

step "verify"
while IFS=$'\t' read -r pkg mode role apks hashes check code; do
  [ -n "$pkg" ] || continue
  [ -n "$check" ] || check=presence
  IFS=',' read -r -a sums <<<"$hashes"
  got=$(vcode "$pkg")
  if [ -z "$got" ]; then
    fail "$pkg is not installed"
  elif [ "$check" = exact ] && [ "$got" != "$code" ]; then
    fail "$pkg has versionCode $got, expected $code"
  elif [ "$check" = exact ]; then
    note "ok        $pkg  code=$got"
  else
    note "ok        $pkg  code=$got (version not pinned)"
  fi
  # Presence packages are never compared against the golden sha256 here: an
  # app that updated itself is fine, and its installed APK legitimately
  # differs from the repo's install source. Only the exact-pinned launcher
  # gets the pulled-APK hash check (unless it was already verified above).
  if [ "$check" != exact ]; then
    continue
  fi
  remote=$(sh_ "pm path $pkg" | sed 's/^package://' | head -1)
  if grep -qx "$pkg" "$WORK/verified.txt"; then
    :                                                            # pulled + hashed above
  elif [ -n "$remote" ]; then
    "$ADB_BIN" -s "$S" pull "$remote" "$WORK/check.apk" >/dev/null 2>&1
    [ "$(sha "$WORK/check.apk")" = "${sums[0]}" ] || fail "$pkg: installed APK differs from the golden sha256"
  fi
done < "$WORK/packages.tsv"

# Config: compare what is on the device with what the repo ships.
HD=/sdcard/Android/data/tv.cleantv.home/files
if have tv.cleantv.home >/dev/null && [ "$(have tv.cleantv.home)" = 1 ]; then
  "$ADB_BIN" -s "$S" pull "$HD/home.conf" "$WORK/home.conf" >/dev/null 2>&1
  if python "$(win "$ROOT/scripts/home_conf.py")" diff "$(win "$ROOT/$HOME_CONF")" \
       "$(win "$WORK/home.conf")" > "$WORK/hc.diff" 2>/dev/null; then
    note "ok        home.conf matches the repo"
  else
    fail "home.conf on the TV differs from $HOME_CONF:"
    sed 's/^/              /' "$WORK/hc.diff" >&2
  fi
  for f in "$ROOT/$ART_DIR"/*.png; do
    [ -f "$f" ] || continue
    "$ADB_BIN" -s "$S" pull "$HD/art/$(basename "$f")" "$WORK/art.png" >/dev/null 2>&1
    if [ -f "$WORK/art.png" ] && cmp -s "$WORK/art.png" "$f"; then note "ok        art/$(basename "$f")"
    else fail "art/$(basename "$f") missing or different on the TV"; fi
    rm -f "$WORK/art.png"
  done
fi

# The debloat the household did, beyond what CleanTV's scripts cover. Packages the
# target does not have at all are not failures (different preinstalled set).
if [ -s "$WORK/disabled.txt" ]; then
  sh_ "pm list packages -d" | sed 's/^package://' | sort > "$WORK/now-disabled.txt"
  missing=""
  while read -r p; do
    [ -n "$p" ] || continue
    grep -qx "$p" "$WORK/now-disabled.txt" && continue
    [ "$(have "$p")" = 1 ] && missing="$missing $p"
  done < "$WORK/disabled.txt"
  if [ -n "$missing" ]; then
    fail "disabled on the captured TV but running here:$missing"
  else
    note "ok        $(wc -l < "$WORK/disabled.txt" | tr -d ' ') disabled packages still disabled"
  fi
fi

# Settings the scripts above are supposed to leave behind.
while IFS=$'\t' read -r key want; do
  [ -n "$key" ] || continue
  [ -n "$want" ] || continue
  case $key in
    always_on_vpn_app) got=$(sh_ "settings get secure $key") ;;
    enabled_accessibility_services) got=$(sh_ "settings get secure $key") ;;
    *) got=$(sh_ "settings get global $key") ;;
  esac
  case $key in
    enabled_accessibility_services)
      printf '%s' "$got" | grep -q 'tv.cleantv.home.Guard' || fail "$key does not include the CleanTV Guard (got '$got')"
      ;;
    *) [ "$got" = "$want" ] && note "ok        $key=$got" || fail "$key is '$got', expected '$want'" ;;
  esac
done < "$WORK/settings.tsv"

# A normal run presses HOME to check the takeover; read-only modes never do.
front=$(front_activity)
if [ "$front" != tv.cleantv.home ] && [ "$VERIFY_ONLY" = 0 ] && [ "$DRY" = 0 ] && [ "$SKIP_SYSTEM" = 0 ]; then
  note "front is '${front:-unknown}' — pressing HOME on the TV to test the takeover"
  sh_ "input keyevent 3" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6; do
    sleep 1
    front=$(front_activity)
    [ "$front" = tv.cleantv.home ] && break
  done
fi
if [ "$VERIFY_ONLY" = 1 ] || [ "$DRY" = 1 ] || [ "$SKIP_SYSTEM" = 1 ]; then
  note "HOME takeover not tested (read-only or --skip-system); press HOME manually to check"
else
case $front in
  tv.cleantv.home) note "ok        HOME lands on CleanTV" ;;
  com.amazon.tv.launcher) fail "HOME goes to Amazon's launcher — the Guard is not taking over" ;;
  "") note "could not read the front activity; press HOME on the TV to check" ;;
  *) fail "after HOME the front activity is $front, not tv.cleantv.home" ;;
esac
fi

echo
if [ "$FAILED" = 0 ]; then
  echo "PASS — $S matches profile '$GUARD_DEVICE / $GUARD_MODEL'."
  echo "Left for you on the TV: sign-ins (Twitch/S0undTV, Kick, Rumble, X, Sozo, Atlantic),"
  echo "and Prime/Netflix if you use them. Nothing here copies accounts."
  echo "App add-ons and other private settings still require manual setup:"
  python "$(win "$ROOT/scripts/source-checklist.py")" "$(win "$ROOT/provision/sources.json")"
else
  echo "FINISHED WITH FAILURES — see the ! lines above." >&2
fi
exit "$FAILED"
