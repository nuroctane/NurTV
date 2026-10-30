#!/usr/bin/env bash
# Build the CleanTV launcher APK from cleantv/launcher/ with the bare SDK tools —
# the same recipe apps/README.md documents, made repeatable.
#
#   ./scripts/build-launcher.sh [--debug]
#
# Writes:
#   cleantv/launcher/build/cleantv-home-<VERSION>.apk   what launcher/install.sh installs
#   apps/cleantv-home.apk                              the repo's copy
# and updates APK_SHA256 in cleantv/launcher/version.env so the installer's checksum
# gate still describes the artifact that exists.
#
# It needs: an Android SDK (platforms + build-tools), a JDK 17+ (Android Studio's
# bundled jbr is found automatically) and python (Git Bash has no `zip`). Signing uses
# private/cleantv.keystore, created on first run — read private/README.md first, the
# key is what lets a build upgrade an installed launcher in place.
set -uo pipefail

# The .exe/.bat tools below need Windows paths; excluding the device prefixes is not
# enough here, so this script converts explicitly with win() instead.
unset MSYS_NO_PATHCONV

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$ROOT/cleantv/launcher
DEBUG=0
[ "${1:-}" = "--debug" ] && DEBUG=1

die() { echo "error: $*" >&2; exit 1; }
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

# ---- version (single source of truth: launcher/version.env) ----------------
[ -f "$SRC/version.env" ] || die "$SRC/version.env is missing"
# shellcheck disable=SC1090,SC1091
source "$SRC/version.env"
: "${VERSION:?version.env has no VERSION}"
: "${VERSION_CODE:?version.env has no VERSION_CODE}"
: "${VERSION_NAME:=$VERSION}"

# ---- SDK, build-tools, JDK --------------------------------------------------
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/AppData/Local/Android/Sdk}}
[ -d "$SDK" ] || die "no Android SDK at $SDK — set ANDROID_HOME"
MIN_SDK=${MIN_SDK:-25}

# Compiling against android-25 is the upstream preference (javac then rejects APIs
# Fire OS 6 lacks); this machine usually only has a newer platform, which is what the
# last hand-built APK used too. Say which one was used.
JAR=""
for p in "$MIN_SDK" 35 34 33 30 28; do
  if [ -f "$SDK/platforms/android-$p/android.jar" ]; then JAR=$SDK/platforms/android-$p/android.jar; break; fi
done
[ -n "$JAR" ] || die "no platforms/android-*/android.jar under $SDK"
[ "$(basename "$(dirname "$JAR")")" = "android-$MIN_SDK" ] || \
  echo "note: compiling against $(basename "$(dirname "$JAR")") (android-$MIN_SDK is not installed)"

BT=$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)
[ -n "$BT" ] || die "no build-tools under $SDK"
for t in aapt2 zipalign; do [ -f "$BT/$t.exe" ] || [ -f "$BT/$t" ] || die "$BT/$t missing"; done

JAVA_POSIX=""
for j in "/c/Program Files/Android/Android Studio/jbr" "$HOME/AppData/Local/Programs/Android Studio/jbr" \
         "${JAVA_HOME:-}" /c/Program\ Files/Java/* /usr/lib/jvm/*; do
  [ -n "$j" ] && [ -x "$j/bin/javac.exe" ] || [ -n "$j" ] && [ -x "$j/bin/javac" ] || continue
  JAVA_POSIX=$j; break
done
[ -n "$JAVA_POSIX" ] || die "no JDK found — install Android Studio or set JAVA_HOME"
export JAVA_HOME; JAVA_HOME=$(win "$JAVA_POSIX")
JAVAC="$JAVA_POSIX/bin/javac"
[ -x "$JAVAC" ] || JAVAC="$JAVA_POSIX/bin/javac.exe"
echo "sdk         $SDK"
echo "build-tools $(basename "$BT")"
echo "jdk         $JAVA_HOME  ($("$JAVAC" -version 2>&1))"
echo "platform    $(basename "$(dirname "$JAR")")  min-sdk $MIN_SDK"

# ---- signing key ------------------------------------------------------------
KEYSTORE=${CLEANTV_KEYSTORE:-$ROOT/private/cleantv.keystore}
KEYPASS=${CLEANTV_KEYPASS:-cleantvhome}
ALIAS=${CLEANTV_KEYALIAS:-cleantv}
mkdir -p "$(dirname "$KEYSTORE")"
if [ ! -f "$KEYSTORE" ]; then
  "$JAVA_POSIX/bin/keytool" -genkeypair -keystore "$(win "$KEYSTORE")" -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 -storepass "$KEYPASS" -keypass "$KEYPASS" \
    -dname "CN=CleanTV" >/dev/null 2>&1 || die "could not create $KEYSTORE"
  echo "created     $KEYSTORE (keep it — a different key cannot upgrade an installed app)"
fi

# apksigner ships as a .bat (needs JAVA_HOME) with a jar beside it (needs java).
signer() {
  if [ -f "$BT/apksigner.bat" ]; then "$BT/apksigner.bat" "$@"; else "$BT/apksigner" "$@"; fi
}
signer_or_jar() {
  if signer "$@" >/dev/null 2>&1; then return 0; fi
  "$JAVA_POSIX/bin/java" -jar "$BT/lib/apksigner.jar" "$@"
}

# ---- build ------------------------------------------------------------------
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cleantv-home.XXXXXX") || die "no temp dir"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/gen" "$WORK/classes" "$SRC/build"

echo
echo "1/6 resources"
( cd "$SRC" && "$BT/aapt2.exe" compile --dir res -o "$(win "$WORK/res.zip")" ) || die "aapt2 compile failed"

echo "2/6 manifest + resources"
( cd "$SRC" && "$BT/aapt2.exe" link -I "$(win "$JAR")" --manifest AndroidManifest.xml \
    "$(win "$WORK/res.zip")" --min-sdk-version "$MIN_SDK" --target-sdk-version 28 \
    --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" \
    --java "$(win "$WORK/gen")" -o "$(win "$WORK/app.apk")" ) || die "aapt2 link failed"

echo "3/6 javac"
# javac and d8 are native tools: the file lists they read must carry Windows paths,
# not the POSIX ones find prints here.
find "$SRC/src" "$WORK/gen" -name '*.java' | while IFS= read -r f; do win "$f"; done > "$WORK/sources.txt"
# -Werror stays on, except for deprecation: upstream compiles against android-25, where
# these APIs are not deprecated yet, while this machine has no android-25 platform and
# builds against a newer jar. Anything else still fails the build.
"$JAVAC" --release 8 -Xlint:all -Xlint:-options -Xlint:-deprecation -Werror -encoding UTF-8 \
  -classpath "$(win "$JAR")" -d "$(win "$WORK/classes")" @"$(win "$WORK/sources.txt")" \
  || die "javac failed"

echo "4/6 dex"
find "$WORK/classes" -name '*.class' | while IFS= read -r f; do win "$f"; done > "$WORK/classes.txt"
"$BT/d8.bat" --release --min-api "$MIN_SDK" --lib "$(win "$JAR")" \
  --output "$(win "$WORK")" @"$(win "$WORK/classes.txt")" || die "d8 failed"
# Git Bash has no `zip`; the dex has to go into the APK before aligning.
python - "$(win "$WORK/app.apk")" "$(win "$WORK/classes.dex")" <<'PY' || die "could not add classes.dex"
import sys, zipfile
apk, dex = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, 'a', zipfile.ZIP_DEFLATED) as z:
    z.write(dex, 'classes.dex')
PY

echo "5/6 align"
"$BT/zipalign.exe" -f -p 4 "$(win "$WORK/app.apk")" "$(win "$WORK/aligned.apk")" || die "zipalign failed"

echo "6/6 sign"
OUT=$SRC/build/cleantv-home-$VERSION.apk
EXTRA=()
[ "$DEBUG" = 1 ] && EXTRA=(--v1-signing-enabled true)
if [ "${#EXTRA[@]}" -gt 0 ]; then
  signer_or_jar sign --ks "$(win "$KEYSTORE")" --ks-pass "pass:$KEYPASS" --key-pass "pass:$KEYPASS" \
    --v1-signing-enabled true --out "$(win "$OUT")" "$(win "$WORK/aligned.apk")" || die "apksigner failed"
else
  signer_or_jar sign --ks "$(win "$KEYSTORE")" --ks-pass "pass:$KEYPASS" --key-pass "pass:$KEYPASS" \
    --out "$(win "$OUT")" "$(win "$WORK/aligned.apk")" || die "apksigner failed"
fi
signer_or_jar verify --print-certs "$(win "$OUT")" | sed -n '1,6p' || die "apksigner verify failed"

cp "$OUT" "$ROOT/apps/cleantv-home.apk"
HASH=$(sha256sum "$OUT" | awk '{print $1}')
if [ "$(sed -n 's/^APK_SHA256=//p' "$SRC/version.env" | head -1)" != "$HASH" ]; then
  sed -i.orig -e "s|^APK_SHA256=.*|APK_SHA256=$HASH|" "$SRC/version.env" && rm -f "$SRC/version.env.orig"
fi

echo
echo "built  ${OUT#"$ROOT"/}  $(wc -c < "$OUT" | tr -d ' ') bytes"
echo "       apps/cleantv-home.apk (same bytes)"
echo "       versionCode $VERSION_CODE, versionName $VERSION_NAME, sha256 ${HASH:0:16}…"
echo
echo "Install it:   ADB_SERIAL=<tv-ip>:5555 cleantv/launcher/install.sh"
echo "Then re-capture so the golden state matches:  ./scripts/capture-tv.sh <tv-ip>"
