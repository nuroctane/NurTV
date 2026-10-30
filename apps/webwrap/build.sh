#!/usr/bin/env bash
# Builds the website wrappers for the Fire TV from the bare SDK tools.
# No Gradle, no libraries, no network.
#
#   ./build.sh              build every app in apps.txt
#   ./build.sh framextv     build one
#
# One dex is compiled and shared; each app differs only by manifest + icons,
# so a new site is a line in apps.txt and two PNGs under icons/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}}
PLATFORM=${PLATFORM:-android-35}
MIN_SDK=${MIN_SDK:-21}
TARGET_SDK=${TARGET_SDK:-28}
BUILD_TOOLS=${BUILD_TOOLS:-35.0.0}

JAR="$SDK/platforms/$PLATFORM/android.jar"
BT="$SDK/build-tools/$BUILD_TOOLS"
KS=${WEBWRAP_KEYSTORE:-${HOME}/.local/share/firetv-keys/webwrap.keystore}
KSPASS=${WEBWRAP_KEYPASS:-webwrap}
VCODE=31
VNAME=3.9.1

only=${1:-}
W=build
OUT=out

die() { echo "error: $*" >&2; exit 1; }
[[ -f $JAR ]] || die "missing $JAR (sdkmanager 'platforms;$PLATFORM')"
[[ -f $BT/aapt2.exe || -f $BT/aapt2 ]] || die "missing $BT (sdkmanager 'build-tools;$BUILD_TOOLS')"
# -f, not -x: sdkmanager unzips the .bat helpers without the exec bit, so an -x
# probe silently falls through to a bare `apksigner` that does not exist.
AAPT2=$BT/aapt2.exe; [ -f "$AAPT2" ] || AAPT2=$BT/aapt2
ZIPALIGN=$BT/zipalign.exe; [ -f "$ZIPALIGN" ] || ZIPALIGN=$BT/zipalign
# java -jar apksigner.jar beats apksigner.bat: no exec bit and no Windows-style
# JAVA_HOME required. Defined as a function below, once the JDK path is known.
APKSIGNER_JAR=$BT/lib/apksigner.jar
D8=$BT/lib/d8.jar

# JDK 17: build-tools' d8 has crashed on newer class files, and the .bat wrappers
# need a WINDOWS-style JAVA_HOME (the POSIX form dies with "Please set JAVA_HOME").
JAVA_POSIX=""
for c in "/c/Program Files/Eclipse Adoptium"/jdk-17* \
         "/c/Program Files/Java"/jdk-17* \
         "/c/Program Files/Eclipse Adoptium"/jdk-21*; do
  [[ -x $c/bin/javac ]] && { JAVA_POSIX=$c; break; }
done
[[ -n $JAVA_POSIX ]] || die "no JDK 17/21 found next to Program Files"
export PATH="$JAVA_POSIX/bin:$PATH"
export JAVA_HOME="$(cygpath -w "$JAVA_POSIX" 2>/dev/null || echo "$JAVA_POSIX")"
echo "jdk: $JAVA_HOME"

apksigner() { "$JAVA_POSIX/bin/java" -jar "$APKSIGNER_JAR" "$@"; }
[[ -f $APKSIGNER_JAR ]] || die "missing $APKSIGNER_JAR"

[[ -f $KS ]] || die "missing signing key at $KS; preserve the existing key outside this project and set WEBWRAP_KEYSTORE"

# ---- js payload syntax check ----------------------------------------------
# One missing quote in a Java string concat ships a dex whose injected JS
# dies with "Unexpected token" on the TV and silently disables chat-hide and
# fullscreen. Parse the payloads BEFORE baking them in.
if command -v node >/dev/null 2>&1; then
  node tools/check-js.js src/tv/webwrap/Main.java || die "JS payload syntax error"
else
  die "node is required to validate embedded JavaScript"
fi

node tools/test-js.js || die "JS behavior regression"
mkdir -p "$W/policy-tests"
javac --release 8 -d "$W/policy-tests" src/tv/webwrap/NavigationPolicy.java tools/NavigationPolicyTest.java
java -cp "$W/policy-tests" NavigationPolicyTest || die "navigation policy regression"

# Source fingerprint is recorded in each APK and its receipt, even without Git.
SOURCE_ID=$(python - <<'PY'
import hashlib, pathlib
h = hashlib.sha256()
for p in sorted([*pathlib.Path('src').rglob('*.java'), pathlib.Path('manifest.template.xml'),
                 pathlib.Path('build.sh'), pathlib.Path('apps.txt')]):
    h.update(p.as_posix().encode()); h.update(p.read_bytes())
print(h.hexdigest())
PY
)
export SOURCE_ID

# ---- shared dex (compiled once) -------------------------------------------
DEX=$W/dex/classes.dex
# Always rebuild: this project is small, and stale bytecode hid previous fixes.
echo "dex: compiling"
  rm -rf "$W/dex"; mkdir -p "$W/dex/classes" "$W/dex/gen"
  find src "$W/dex/gen" -name '*.java' > "$W/dex/sources.txt"
  javac --release 8 -Xlint:-options -encoding UTF-8 \
    -classpath "$JAR" -d "$W/dex/classes" @"$W/dex/sources.txt"
  find "$W/dex/classes" -name '*.class' > "$W/dex/classlist.txt"
  java -cp "$D8" com.android.tools.r8.D8 --release --min-api "$MIN_SDK" \
    --lib "$JAR" --output "$W/dex" @"$W/dex/classlist.txt"
  [[ -f $DEX ]] || die "d8 produced no classes.dex"

# ---- per app --------------------------------------------------------------
mkdir -p "$OUT"
made=0
while IFS='|' read -r slug pkg label url icon flags hosts; do
  # strip CR: this file is edited on Windows, and a trailing \r makes
  # `-f icons/x.png` fail on a file that plainly exists
  slug=${slug%$'\r'}; pkg=${pkg%$'\r'}; label=${label%$'\r'}
  url=${url%$'\r'}; icon=${icon%$'\r'}; flags=${flags%$'\r'}
  hosts=${hosts%$'\r'}
  [[ -z ${slug:-} || ${slug:0:1} == '#' ]] && continue
  [[ -n $only && $slug != "$only" ]] && continue
  [[ -f $icon ]] || die "$slug: icon not found: $icon"

  echo
  echo "== $slug ($pkg) =="
  A=$(cygpath -w "$(pwd)")/$W/$slug
  rm -rf "$W/$slug"; mkdir -p "$W/$slug/res/drawable-nodpi"
  cp "$icon" "$W/$slug/res/drawable-nodpi/icon.png"

  # leanback banner is 320x180; a per-app override beats the generated one
  if [[ -f icons/$slug-banner.png ]]; then
    cp "icons/$slug-banner.png" "$W/$slug/res/drawable-nodpi/banner.png"
    echo "   banner: icons/$slug-banner.png"
  else
    ffmpeg -hide_banner -loglevel error -y \
      -f lavfi -i "color=c=0x07070c:s=320x180" -i "$icon" \
      -filter_complex "[1:v]scale=150:150:force_original_aspect_ratio=decrease:flags=lanczos[lg];[0:v][lg]overlay=(W-w)/2:(H-h)/2" \
      -frames:v 1 "$W/$slug/res/drawable-nodpi/banner.png"
    echo "   banner: generated from $icon"
  fi

  VCODE="$VCODE" VNAME="$VNAME" python - "$slug" "$pkg" "$label" "$url" "$flags" "$hosts" <<'PY'
import sys, pathlib
import os
slug, pkg, label, url = sys.argv[1:5]
flags = (sys.argv[5] if len(sys.argv) > 5 else "").strip()
flags = set(flags.split(',')) - {''}
assert flags <= {'nochat', 'legacy-http', 'third-party-cookies', 'diagnostics'}, 'unknown compatibility flag'
STRIP = "0"  # The removed NTV wrapper was the only sandbox exception.
HIDECHAT = "1" if "nochat" in flags else "0"
hosts = sys.argv[6].strip()
import re
from urllib.parse import urlsplit
u = urlsplit(url)
assert u.scheme == 'https' and u.hostname and not u.username and not u.password and u.port in (None, 443), 'invalid home URL'
assert all(re.fullmatch(r'[a-zA-Z0-9.-]+', x) for x in hosts.split(',') if x), 'invalid navigation host'
VCODE, VNAME = os.environ["VCODE"], os.environ["VNAME"]
tpl = pathlib.Path("manifest.template.xml").read_text(encoding="utf-8")
esc = lambda s: s.replace("&", "&amp;").replace("<", "&lt;").replace('"', "&quot;")
out = (tpl.replace("__PKG__", pkg)
          .replace("__LABEL__", esc(label))
          .replace("__URL__", esc(url))
          .replace("__STRIP__", STRIP)
          .replace("__HIDECHAT__", HIDECHAT)
          .replace("__HTTP__", 'true' if 'legacy-http' in flags else 'false')
          .replace("__HTTPFLAG__", '1' if 'legacy-http' in flags else '0')
          .replace("__COOKIES__", '1' if 'third-party-cookies' in flags else '0')
          .replace("__HOSTS__", esc(hosts))
          .replace("__DIAG__", '1' if 'diagnostics' in flags else '0')
          .replace("__BUILD__", os.environ['SOURCE_ID'])
          .replace("__VCODE__", VCODE)
          .replace("__VNAME__", VNAME))
pathlib.Path(f"build/{slug}/AndroidManifest.xml").write_text(out, encoding="utf-8")
PY

  "$AAPT2" compile --dir "$W/$slug/res" -o "$W/$slug/res.zip"
  "$AAPT2" link -I "$JAR" --manifest "$W/$slug/AndroidManifest.xml" "$W/$slug/res.zip" \
    --min-sdk-version "$MIN_SDK" --target-sdk-version "$TARGET_SDK" \
    --version-code "$VCODE" --version-name "$VNAME" --java "$W/$slug/gen" -o "$W/$slug/app.apk"

  # add the shared dex (python stands in for `zip`, which Git Bash lacks)
  python - "$A" <<'PY'
import sys, zipfile, pathlib
root = pathlib.Path(sys.argv[1])
apk = root / "app.apk"
with zipfile.ZipFile(apk, "a", zipfile.ZIP_DEFLATED) as z:
    z.write(root.parent / "dex" / "classes.dex", "classes.dex")
PY

  "$ZIPALIGN" -f -p 4 "$W/$slug/app.apk" "$W/$slug/aligned.apk"
  apksigner sign --ks "$KS" --ks-pass "pass:$KSPASS" --key-pass "pass:$KSPASS" \
    --out "$OUT/$slug-tv.apk" "$W/$slug/aligned.apk"
  apksigner verify "$OUT/$slug-tv.apk"
  python - "$OUT/$slug-tv.apk" "$pkg" "$VNAME" "$VCODE" <<'PY'
import hashlib, json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
p.with_suffix('.json').write_text(json.dumps(dict(package=sys.argv[2], version=sys.argv[3],
    versionCode=int(sys.argv[4]), source_sha256=os.environ['SOURCE_ID'],
    apk_sha256=hashlib.sha256(p.read_bytes()).hexdigest()), indent=2) + '\n')
PY
  printf '   -> %s  %s bytes\n' "$OUT/$slug-tv.apk" "$(wc -c < "$OUT/$slug-tv.apk" | tr -d ' ')"
  made=$((made + 1))
done < apps.txt

echo
echo "built $made apk(s) in $OUT/"
