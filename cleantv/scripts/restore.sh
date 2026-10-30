#!/usr/bin/env bash
# Undoes the package, app-op, network-policy, launcher and DNS changes.
# Apps that were uninstalled from /data have to be reinstalled from the store.
# Usage: ./scripts/restore.sh [--dry-run] [-y]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_flags "$@"
need_device
load_conf

# Everything debloat.sh or youtube.sh may have switched off, under any answers.
restore_list() {
  {
    list_of "$(fos packages.txt)"
    list_of "$(fos alexa.txt)"
    list_of "$(fos user-apps.txt)"
    printf '%s\n' $REMOVE_EXTRA com.amazon.firetv.youtube
  } | awk 'NF {print $1}' | awk '!seen[$0]++'
}

step "plan"
note "restore recorded package overrides; legacy installs without a ledger use enable defaults"
note "clear app-ops and network blacklists"
note "detach the DNS filter and the launcher hook"
note "put back every setting from report/settings-before-*.txt, or the bundled defaults"
note "the TV reboots when this finishes"
if [[ $DRY_RUN == 0 ]]; then
  confirm "Restore Amazon defaults on $SERIAL?" || die "cancelled"
fi

mkdir -p "$REPORT"

# Prefer the value this device actually had before the pass (snapshotted by
# preflight.sh); fall back to the stock defaults in data/.
restore_value() {
  local ns=$1 key=$2 fallback=$3 snapshot="$REPORT/settings-before-$1.txt" v
  if [[ -f $snapshot ]]; then
    v=$(grep -m1 "^$key=" "$snapshot" 2>/dev/null | cut -d= -f2-)
    if grep -q "^$key=" "$snapshot"; then printf '%s' "$v"
    else printf 'null'; fi
    return
  fi
  printf '%s' "$fallback"
}

restore_package_state() {
  local p=$1 state verb out
  if [[ -f $REPORT/package-states-before.tsv ]]; then
    state=$(awk -F '\t' -v p="$p" '$1==p {print $2; exit}' "$REPORT/package-states-before.tsv")
    [[ -n $state ]] || { note "$p: no recorded mutation, leaving package state unchanged"; return; }
    case $state in
      0) verb=default-state ;; 1) verb=enable ;; 2) verb=disable ;;
      3) verb=disable-user ;; 4) verb=disable-until-used ;;
      *) die "invalid package snapshot for $p" ;;
    esac
  else
    verb=enable
  fi
  out=$(acmd pm "$verb" --user 0 "$p")
  [[ $DRY_RUN == 1 || $out == *"new state:"* ]] || die "could not restore package $p: $out"
  printf '  %-46s %s\n' "$p" "$out"
}

step "packages"
[[ -f $REPORT/package-states-before.tsv ]] || note "legacy restore: no exact package snapshot; using documented enable defaults"
for p in $(restore_list); do
  # Older versions uninstalled some system apps for user 0; install-existing brings
  # those back where the build has it. Store apps come back from the store.
  if ! present "$p"; then
    [[ $REINSTALL == 1 ]] || continue
    a=$(acmd cmd package install-existing "$p" 2>&1 | head -1)
    present "$p" || continue
  else
    a="installed"
  fi
  restore_package_state "$p"
  bg_on "$p"
  uid=$(uid_of "$p")
  [[ -n $uid ]] && acmd cmd netpolicy remove restrict-background-blacklist "$uid" >/dev/null 2>&1
done

# Older lists disabled packages that have since moved to never-disable.txt
# (com.amazon.firebat is Prime Video), so the loop above no longer reaches them.
step "never-disable packages left disabled"
off=$(dev 'pm list packages -d' | sed 's/^package://' | tr -d '\r')
for p in $(list_of "$(fos never-disable.txt)" | awk '{print $1}'); do
  grep -qx "$p" <<<"$off" || continue
  restore_package_state "$p"
done

step "screensaver"
if [[ $(dev1 settings get secure screensaver_components) == "$AOSP_DREAM" ]]; then
  want=$(restore_value secure screensaver_components "$(dev1 settings get secure screensaver_default_component)")
  if [[ -n $want && $want != null && $want != "$AOSP_DREAM" ]]; then
    acmd settings put secure screensaver_components "$want" >/dev/null
    printf '  %-46s %s\n' screensaver_components "$want"
  fi
else
  note "unchanged"
fi

step "packages that were only starved"
if [[ -f $REPORT/debloat.txt ]]; then
  while IFS=$'\t' read -r p state rest; do
    [[ -z ${p:-} ]] && continue
    bg_on "$p"
    uid=$(uid_of "$p")
    [[ -n $uid ]] && acmd cmd netpolicy remove restrict-background-blacklist "$uid" >/dev/null 2>&1
    printf '  %-46s %s\n' "$p" "${state:-unknown}"
  done < "$REPORT/debloat.txt"
else
  note "no report/debloat.txt, relying on protected.txt only"
  for p in $(list_of "$(fos protected.txt)"); do
    bg_on "$p"
    uid=$(uid_of "$p")
    [[ -n $uid ]] && acmd cmd netpolicy remove restrict-background-blacklist "$uid" >/dev/null 2>&1
    printf '  %-46s cleared\n' "$p"
  done
fi
acmd cmd netpolicy set restrict-background false >/dev/null 2>&1

step "on-device hooks"
# Without this the TV keeps sending DNS through a filter the user just tried to
# undo, and HOME stays hijacked.
acmd settings delete secure always_on_vpn_app >/dev/null 2>&1
if [[ $DRY_RUN == 1 ]]; then
  note "[dry-run] ADB=$ADB ADB_SERIAL=$SERIAL launcher/install.sh --undo"
else
  ADB=$ADB ADB_SERIAL=$SERIAL "$ROOT/launcher/install.sh" --undo >/dev/null ||
    die "could not hand HOME back to Amazon's launcher; run ./launcher/install.sh --undo"
fi
note "always_on_vpn_app cleared, HOME handed back to Amazon's launcher (apps stay installed)"

step "settings"
while read -r ns key value; do
  [[ -z ${ns:-} || $ns == \#* ]] && continue
  want=$(restore_value "$ns" "$key" "$value")
  if [[ $want == null ]]; then acmd settings delete "$ns" "$key" >/dev/null
  else acmd settings put "$ns" "$key" "${want:-\"\"}" >/dev/null; fi
  printf '  %-46s %s\n' "$key" "$want"
done < <(list_of "$(fos settings.restore.txt)" | sed 's/ = / /')

# The filter also starts from its own boot receiver, so clearing always_on_vpn_app
# alone leaves it filtering after the reboot. Disabling it stops the VPN, which can
# cut a network adb session, so it goes last.
if present dnsfilter.android; then
  step "DNS filter"
  acmd pm disable-user --user 0 dnsfilter.android >/dev/null 2>&1
  note "personalDNSfilter disabled (it would start again at boot); dnsfilter.sh turns it back on"
  [[ $DRY_RUN == 1 ]] || { sleep 3; adb_reconnect; }
fi

[[ $DRY_RUN == 1 ]] && { note "[dry-run] done"; exit 0; }
reboot_wait
note "restored. CleanTV home, personalDNSfilter and SmartTube (if you added it) are still"
note "installed; remove them in Settings > Applications if you want them gone too."
