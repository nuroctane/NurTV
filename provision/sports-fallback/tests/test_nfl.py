import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from nfl import nfl_rank  # noqa: E402


class NflRankTest(unittest.TestCase):
    def test_national_carriers_rank_first(self):
        for name in ["NFL Network", "ESPN", "ESPN 2", "ESPN2 HD", "FOX Sports 1", "Fox Deportes", "NFL Channel"]:
            self.assertEqual(nfl_rank(name)[0], 0, name)
        self.assertLess(nfl_rank("NFL Network"), nfl_rank("ESPN"))
        self.assertLess(nfl_rank("ESPN"), nfl_rank("NFL Channel"))

    def test_local_network_stations(self):
        for name in ["FOX 2 Detroit", "CBS KIRO-TV (1080p)", "NBC WMAQ-TV (1080p)", "ABC KGTV (1080p)"]:
            self.assertEqual(nfl_rank(name)[0], 1, name)

    def test_not_game_carriers(self):
        for name in ["CBS News 24/7", "FOX Weather", "LiveNOW from FOX", "CBS Sports Golazo Network",
                     "ESPN (Brazil) (1080p)", "ESPN 4 (Brazil) (1080p)", "FOX LOCAL Chicago",
                     "ABC WBRZ-TV [Geo-blocked]", "NBC News NOW", "DAZN 1", "ESPN Premium", "ESPNU", "Fox Business Network (576p)",
                     "FOX Central (1080p)", "CBS en espanol", "FOX Sports"]:
            self.assertIsNone(nfl_rank(name), name)


if __name__ == "__main__":
    unittest.main()
