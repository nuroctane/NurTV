"""Shared helpers in scripts/lib.sh, run against a fake ADB.

Run: python3 -m unittest discover -s tests -v
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

# Prints the match first, then keeps writing like a long `cmd package help`.
# A reader that stops at the first match makes it die of SIGPIPE, as real adb does.
FAKE_ADB = r'''#!/usr/bin/env bash
case "$*" in
  start-server) exit 0 ;;
  "-s test-tv shell getprop ro.build.version.sdk") echo 30 ;;
  "-s test-tv shell cmd package help")
    echo "  install-existing [--user USER_ID] PACKAGE"
    sleep 0.2
    yes "  help text" | head -c 1000000 ;;
  *) exit 92 ;;
esac
'''


class NeedDeviceTest(unittest.TestCase):
    def test_install_existing_detected_under_pipefail(self):
        with tempfile.TemporaryDirectory() as tmp:
            adb = Path(tmp) / "adb"
            adb.write_text(FAKE_ADB)
            adb.chmod(0o755)
            env = dict(os.environ, ADB=str(adb), ADB_SERIAL="test-tv")
            result = subprocess.run(
                ["bash", "-c",
                 'set -uo pipefail; source "$1"; need_device; echo "REINSTALL=$REINSTALL"',
                 "bash", str(ROOT / "scripts" / "lib.sh")],
                env=env, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("REINSTALL=1", result.stdout)


def lib(script, env=None):
    return subprocess.run(
        ["bash", "-c", 'set -uo pipefail; source "$1"; ' + script,
         "bash", str(ROOT / "scripts" / "lib.sh")],
        env=dict(os.environ, **(env or {})), capture_output=True, text=True,
    )


class PackageSnapshotTest(unittest.TestCase):
    def test_first_state_survives_a_later_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            adb = Path(tmp) / "adb"
            adb.write_text('#!/usr/bin/env bash\necho "User 0: installed=true enabled=${ORIGINAL_STATE:-2} hidden=false"\n')
            adb.chmod(0o755)
            env = {"ADB": str(adb), "SERIAL": "test", "REPORT": tmp}
            first = lib('snapshot_package_state com.example.app', env)
            second = lib('snapshot_package_state com.example.app', dict(env, ORIGINAL_STATE="1"))
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual((Path(tmp) / 'package-states-before.tsv').read_text(), 'com.example.app\t2\n')

    def test_unreadable_state_refuses_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            adb = Path(tmp) / "adb"
            adb.write_text('#!/usr/bin/env bash\necho "error: device offline"\nexit 1\n')
            adb.chmod(0o755)
            result = lib('snapshot_package_state com.example.app; echo unsafe',
                         {"ADB": str(adb), "SERIAL": "test", "REPORT": tmp})
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('unsafe', result.stdout)


class FallbackDnsTest(unittest.TestCase):
    def line(self, upstream):
        result = lib('fallback_dns', {"DNS_UPSTREAM": upstream})
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_empty_keeps_the_router(self):
        self.assertEqual(self.line(""), "")

    def test_only_spaces_keeps_the_router(self):
        self.assertEqual(self.line("   "), "")

    def test_v4_and_v6(self):
        self.assertEqual(
            self.line("76.76.2.45  2606:1a40::45"),
            "[76.76.2.45]::53::UDP; [2606:1a40::45]::53::UDP",
        )

    def test_full_v6(self):
        self.assertEqual(self.line("2001:db8:0:0:0:0:0:1"), "[2001:db8:0:0:0:0:0:1]::53::UDP")

    def test_what_is_not_a_resolver_is_refused(self):
        for bad in ("one.one.one.one", "999.1.1.1", "1.2.3.4.5", "1.2.3", "0.0.0.0",
                    "::", ":::1", "1::2::3", "12345::1", "dead.beef.c0de.1",
                    "1.1.1.1:53", "1.1.1.1;evil", "1.1.1.1#x", "[::1]"):
            with self.subTest(bad=bad):
                result = lib('fallback_dns', {"DNS_UPSTREAM": bad})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")


class FrontActivityTest(unittest.TestCase):
    DUMPS = {
        "fire os 6": "  Stack #1:\n    mResumedActivity: ActivityRecord{2b u0 tv.cleantv.home/.Home t12}\n",
        "fire os 7": ("    mResumedActivity: ActivityRecord{772d87b u0 tv.cleantv.home/.Home t1954}\n"
                      "  ResumedActivity: ActivityRecord{772d87b u0 tv.cleantv.home/.Home t1954}\n"),
        "android 13": "  * Task{a #9}\n      topResumedActivity=ActivityRecord{9 u0 tv.cleantv.home/.Home t9}\n",
        "android 14": ("  * Task{aad0114 #106 type=standard A=10129:com.amazon.screensaver U=0}\n"
                       "    topResumedActivity=ActivityRecord{22a6f67 u0 com.amazon.screensaver/.MainActivity t106}\n"
                       "  * Task{b #2 type=home}\n"
                       "      topResumedActivity=ActivityRecord{3 u0 tv.cleantv.home/.Home t2}\n"
                       "  ResumedActivity: ActivityRecord{22a6f67 u0 com.amazon.screensaver/.MainActivity t106}\n"),
    }
    WANT = {
        "fire os 6": "tv.cleantv.home/.Home",
        "fire os 7": "tv.cleantv.home/.Home",
        "android 13": "tv.cleantv.home/.Home",
        "android 14": "com.amazon.screensaver/.MainActivity",
    }

    def test_every_android_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            adb = Path(tmp) / "adb"
            adb.write_text('#!/usr/bin/env bash\ncat "$DUMP"\n')
            adb.chmod(0o755)
            for name, dump in self.DUMPS.items():
                with self.subTest(name=name):
                    (Path(tmp) / "dump").write_text(dump)
                    result = lib("front_activity", {"ADB": str(adb), "SERIAL": "tv",
                                                    "DUMP": str(Path(tmp) / "dump")})
                    self.assertEqual(result.stdout.strip(), self.WANT[name], result.stderr)


class FireOsNameTest(unittest.TestCase):
    def name(self, sdk):
        return lib("fireos_name", {"SDK": str(sdk)}).stdout.strip()

    def test_each_generation(self):
        self.assertEqual(self.name(22), "Fire OS 5 or older (unsupported)")
        self.assertEqual(self.name(25), "Fire OS 6")
        self.assertEqual(self.name(28), "Fire OS 7")
        self.assertEqual(self.name(30), "Fire OS 8")
        self.assertEqual(self.name(34), "Fire OS newer than 8 (sdk 34, untested)")


AMAZON_ADB = "\n".join([
    "#!/usr/bin/env bash",
    'case "$*" in',
    "  '-s test-tv shell getprop ro.product.manufacturer') printf 'Amazon\\r\\n' ;;",
    "  *) exit 92 ;;",
    "esac",
]) + "\n"


class SupportedFireOsTest(unittest.TestCase):
    def run_with_sdk(self, sdk):
        with tempfile.TemporaryDirectory() as tmp:
            adb = Path(tmp) / "adb"
            adb.write_text(AMAZON_ADB)
            adb.chmod(0o755)
            return lib("need_supported_fireos && echo ok",
                       {"ADB": str(adb), "ADB_SERIAL": "test-tv", "SDK": str(sdk)})

    def test_fire_os_5_is_refused(self):
        result = self.run_with_sdk(22)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Fire OS 5", result.stderr)

    def test_fire_os_6_passes(self):
        result = self.run_with_sdk(25)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "ok")

    def test_dev1_strips_carriage_return(self):
        with tempfile.TemporaryDirectory() as tmp:
            adb = Path(tmp) / "adb"
            adb.write_text(AMAZON_ADB)
            adb.chmod(0o755)
            result = lib('[[ $(dev1 getprop ro.product.manufacturer) == Amazon ]] && echo exact',
                         {"ADB": str(adb), "ADB_SERIAL": "test-tv"})
        self.assertEqual(result.stdout.strip(), "exact", result.stderr)


if __name__ == "__main__":
    unittest.main()
