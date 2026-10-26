import functools
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from http.server import ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from preview_server import PreviewHandler


class QuietPreviewHandler(PreviewHandler):
    def log_message(self, *_):
        pass


class PreviewSnapshotStatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='parcelhub-preview-tests-')
        cls.root = Path(cls.temp.name)
        (cls.root / '.private').mkdir()
        cls.snapshot = cls.root / '.private' / 'official-snapshot.json'
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietPreviewHandler, directory=str(cls.root)))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f'http://127.0.0.1:{cls.server.server_port}/api/official-snapshot'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)
        assert cls.root.resolve().parent == Path(tempfile.gettempdir()).resolve()
        cls.temp.cleanup()

    def write_snapshot(self, value):
        self.snapshot.write_text(json.dumps(value), encoding='utf-8')

    def test_ready_snapshot_is_returned(self):
        snapshot = {'state': 'ready', 'parcels': [], 'expectedCount': 0, 'readAt': 'fixture'}
        self.write_snapshot(snapshot)
        with urlopen(self.url, timeout=3) as response:
            self.assertEqual(json.load(response), snapshot)

    def test_incomplete_states_return_status_without_partial_parcels(self):
        for state in ('login_required', 'loading', 'error'):
            with self.subTest(state=state):
                self.write_snapshot({'state': state, 'message': '测试状态', 'parcels': [{'title': '不得当成完整清单'}]})
                with urlopen(self.url, timeout=3) as response:
                    self.assertEqual(json.load(response), {'state': state, 'message': '测试状态'})

    def test_unknown_state_is_rejected(self):
        self.write_snapshot({'state': 'unknown', 'parcels': []})
        with self.assertRaises(HTTPError) as caught:
            urlopen(self.url, timeout=3)
        self.assertEqual(caught.exception.code, 503)

    def test_non_local_host_cannot_read_snapshot(self):
        self.write_snapshot({'state': 'ready', 'parcels': []})
        with self.assertRaises(HTTPError) as caught:
            urlopen(Request(self.url, headers={'Host': 'example.invalid'}), timeout=3)
        self.assertEqual(caught.exception.code, 403)


if __name__ == '__main__':
    unittest.main()
