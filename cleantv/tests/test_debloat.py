"""debloat.sh against a pretend Fire TV: what it disables, and what it never touches.

Run: python3 -m unittest discover -s tests -v
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "fireos"


def entries(path):
    out = []
    for line in path.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(line.split()[0])
    return out


CLEANUP = entries(DATA / "packages.txt")
ALEXA = entries(DATA / "alexa.txt")
USER_APPS = entries(DATA / "user-apps.txt")
STORE_APPS = ["com.netflix.ninja", "com.amazon.firetv.youtube", "org.videolan.vlc",
              "in.startv.hotstar", "com.zee5.amazon"]


class DebloatTest(unittest.TestCase):
    AMAZON_DREAM = "com.amazon.ftv.screensaver/.app.services.ScreensaverService"

    def run_debloat(self, conf="", *flags, basic_dream=True):
        packages = {p: {"system": True, "enabled": True} for p in CLEANUP + ALEXA + USER_APPS}
        if basic_dream:
            packages["com.android.dreams.basic"] = {"system": True, "enabled": True}
        for p in STORE_APPS:
            packages[p] = {"system": False, "enabled": True}
        packages["com.amazon.tv.launcher"] = {"system": True, "enabled": True}
        packages["com.amazon.device.metrics"] = {"system": True, "enabled": True, "protected": True}
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            state = tmp / "state.json"
            state.write_text(json.dumps({"packages": packages, "settings": {
                "secure/screensaver_components": self.AMAZON_DREAM}}))
            log = tmp / "commands.log"
            log.touch()
            (tmp / "cleantv.conf").write_text(conf)
            env = dict(os.environ, ADB=str(ROOT / "tests" / "fake_tv.py"), ADB_SERIAL="test-tv",
                       FAKE_TV_STATE=str(state), FAKE_TV_LOG=str(log), CONF=str(tmp / "cleantv.conf"), REPORT=str(tmp / "report"))
            env.pop("REMOVE_EXTRA", None)
            env.pop("KEEP_APPS", None)
            env.pop("ALEXA", None)
            result = subprocess.run(
                ["bash", str(ROOT / "scripts" / "debloat.sh"), "-y", "--no-reboot", *flags],
                env=env, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            commands = log.read_text().splitlines()
        disabled = {c.split()[-1] for c in commands if c.startswith("pm disable-user")}
        uninstalled = {c.split()[-1] for c in commands if c.startswith("pm uninstall")}
        settings = [c for c in commands if c.startswith("settings put")]
        return disabled, uninstalled, settings

    def test_default_touches_no_app(self):
        disabled, uninstalled, _ = self.run_debloat()
        self.assertEqual(uninstalled, set())
        self.assertEqual(disabled, set(CLEANUP))
        self.assertFalse(disabled & set(USER_APPS + STORE_APPS))

    def test_default_keeps_alexa_and_voice(self):
        disabled, _, settings = self.run_debloat()
        self.assertFalse(disabled & set(ALEXA))
        self.assertFalse([s for s in settings if "voice_disabled" in s or "alexa_wake_word" in s])

    def test_alexa_off_only_when_asked(self):
        disabled, _, settings = self.run_debloat("ALEXA=0\n")
        self.assertTrue(set(ALEXA) <= disabled)
        self.assertTrue([s for s in settings if "voice_disabled" in s])

    def test_only_named_apps_are_removed(self):
        conf = 'REMOVE_EXTRA="in.startv.hotstar com.amazon.cloud9"\n'
        disabled, uninstalled, _ = self.run_debloat(conf)
        self.assertEqual(uninstalled, {"in.startv.hotstar"})
        self.assertIn("com.amazon.cloud9", disabled)
        self.assertNotIn("com.zee5.amazon", uninstalled | disabled)
        self.assertNotIn("com.amazon.firetv.youtube", uninstalled | disabled)

    def test_never_disable_wins_over_a_named_app(self):
        disabled, uninstalled, _ = self.run_debloat('REMOVE_EXTRA="com.amazon.tv.launcher"\n')
        self.assertNotIn("com.amazon.tv.launcher", disabled | uninstalled)

    def test_keep_list_wins_over_the_cleanup_list(self):
        disabled, _, _ = self.run_debloat('KEEP_APPS="com.amazon.tv.acr"\n')
        self.assertNotIn("com.amazon.tv.acr", disabled)

    def test_screensaver_left_alone_by_default(self):
        _, _, settings = self.run_debloat()
        self.assertFalse([s for s in settings if "screensaver" in s])

    def test_disabled_screensaver_is_replaced_by_androids_own(self):
        disabled, _, settings = self.run_debloat('REMOVE_EXTRA="com.amazon.ftv.screensaver"\n')
        self.assertIn("com.amazon.ftv.screensaver", disabled)
        self.assertIn("settings put secure screensaver_components com.android.dreams.basic/.Colors",
                      settings)

    def test_no_replacement_screensaver_means_no_change(self):
        _, _, settings = self.run_debloat('REMOVE_EXTRA="com.amazon.ftv.screensaver"\n',
                                          basic_dream=False)
        self.assertFalse([s for s in settings if "screensaver" in s])

    def test_dry_run_changes_nothing(self):
        disabled, uninstalled, settings = self.run_debloat("", "--dry-run")
        self.assertEqual((disabled, uninstalled, settings), (set(), set(), []))


if __name__ == "__main__":
    unittest.main()
