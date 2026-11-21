import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'build-fallback-m3u.py'
spec = importlib.util.spec_from_file_location('sports_builder', SCRIPT)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def playlist(count, prefix='channel'):
    return '#EXTM3U\n' + ''.join(
        f'#EXTINF:-1 group-title="Sports",{prefix}{n}\n'
        f'#EXTVLCOPT:http-user-agent=Test\nhttps://example.test/{prefix}{n}.m3u8\n'
        for n in range(count))


class ReliabilityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous = os.getcwd()
        os.chdir(self.temp.name)
        self.sources = [{'name': 'one', 'url': 'one', 'sports_only': True},
                        {'name': 'two', 'url': 'two', 'sports_only': True}]
        self.source_patch = patch.object(builder, 'SOURCES', self.sources)
        self.source_patch.start()

    def tearDown(self):
        self.source_patch.stop()
        os.chdir(self.previous)
        self.temp.cleanup()

    def test_initial_failure_preserves_existing_playlist(self):
        Path('sports-fallback.m3u').write_text('original', encoding='utf8')
        def fetch(url):
            if url == 'one': return playlist(2)
            raise OSError('failed')
        with patch.object(builder, 'fetch', side_effect=fetch):
            self.assertEqual(builder.main(), 1)
        self.assertEqual(Path('sports-fallback.m3u').read_text(), 'original')
        self.assertFalse(Path('source-cache.json').exists())

    def test_cached_source_survives_failure_and_partial_response(self):
        with patch.object(builder, 'fetch', side_effect=lambda u: playlist(12, u)):
            self.assertEqual(builder.main(), 0)
        with patch.object(builder, 'fetch', side_effect=lambda u: playlist(2, u) if u == 'one' else (_ for _ in ()).throw(OSError())):
            self.assertEqual(builder.main(), 0)
        stats = json.loads(Path('stats.json').read_text())
        self.assertEqual(stats['total'], 24)
        self.assertEqual(stats['sources']['one']['status'], 'cached')
        self.assertEqual(stats['sources']['two']['status'], 'cached')
        self.assertIn('#EXTVLCOPT:http-user-agent=Test', Path('sports-fallback.m3u').read_text())

    def test_private_query_and_malformed_playlist_rejected(self):
        self.assertFalse(builder.public_url('https://example.test/a?key=secret'))
        self.assertFalse(builder.public_url('https://user:pass@example.test/a'))
        with self.assertRaises(ValueError): builder.parse_m3u('<html>not a playlist</html>')
        self.assertEqual(len(builder.parse_m3u(playlist(1).replace('#EXTM3U', '#EXTM3U url-tvg="https://example.test/guide.xml"', 1))), 1)


if __name__ == '__main__':
    unittest.main()
