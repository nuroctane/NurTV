# scripts/_adb.sh — shared adb locator. Source it, do not run it.
#
# Sets ADB_BIN and prepends its directory to PATH.
# Deliberately never references $USER: MSYS2/UCRT64 leaves it unset, and the
# scripts run under `set -u`, which turns that into "USER: unbound variable".

adb_candidates() {
  [ -n "${HOME:-}" ] && printf '%s\n' "$HOME/AppData/Local/Android/Sdk/platform-tools"
  if [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
    printf '%s\n' "$(cygpath -u "$LOCALAPPDATA" 2>/dev/null)/Android/Sdk/platform-tools"
  fi
  [ -n "${USERNAME:-}" ] && printf '%s\n' "/c/Users/$USERNAME/AppData/Local/Android/Sdk/platform-tools"
  printf '%s\n' "/c/Program Files/Android/platform-tools"
  printf '%s\n' "/usr/local/bin" "/usr/bin" "/opt/homebrew/bin"
}

require_adb() {
  [ -n "${ADB_BIN:-}" ] && return 0
  local d name found="" n=0 p
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    for name in adb adb.exe; do
      if [ -x "$d/$name" ]; then found="$found$d/$name"$'\n'; n=$((n+1)); break; fi
    done
  done < <(adb_candidates)
  if command -v adb >/dev/null 2>&1; then
    p=$(command -v adb)
    case "$found" in *"$p"*) ;; *) found="$found$p"$'\n'; n=$((n+1));; esac
  fi
  if [ "$n" -eq 0 ]; then
    echo "adb not found." >&2
    echo "  install: winget install Google.PlatformTools" >&2
    echo "  then open a NEW shell — PATH only refreshes in new shells." >&2
    return 1
  fi
  ADB_BIN=$(printf '%s' "$found" | head -1)
  export ADB_BIN
  export PATH="$(dirname "$ADB_BIN"):$PATH"
  if [ "$n" -gt 1 ] && [ "${ADB_VERBOSE:-0}" = 1 ]; then
    echo "note: $n adb binaries present; pinned to $ADB_BIN" >&2
    echo "      (set ADB_BIN explicitly to override)" >&2
  fi
  return 0
}
