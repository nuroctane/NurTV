import gzip
import importlib.util
import tempfile
import unittest
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'audit-guide.py'
spec = importlib.util.spec_from_file_location('guide_audit', SCRIPT)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class GuideAuditTest(unittest.TestCase):
    def test_exact_ids_and_unambiguous_future_times(self):
        guide = b'''<tv><channel id="sports.us"><display-name>Sports</display-name></channel>
          <programme channel="sports.us" stop="20300101000000 +0000"><title>Game</title></programme>
          <programme channel="sports.us" stop="20300101000000"><title>Unknown zone</title></programme>
          <programme channel="sports.us" stop="20200101000000 +0000"><title>Old</title></programme></tv>'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'guide.xml.gz'
            with gzip.open(path, 'wb') as stream: stream.write(guide)
            channels, counts = audit.read_guide(path, datetime(2026, 1, 1, tzinfo=timezone.utc))
            self.assertEqual(channels, {'sports.us'})
            self.assertEqual(counts, Counter({'sports.us': 1}))
            playlist = Path(directory) / 'channels.m3u'
            playlist.write_text('#EXTM3U\n#EXTINF:-1 tvg-id="sports.us",Sports\nhttps://example.test\n#EXTINF:-1,No ID\nhttps://example.test/2\n')
            self.assertEqual(audit.read_ids(playlist), ['sports.us', ''])


if __name__ == '__main__': unittest.main()
