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

    def test_empty_candidate_retains_read_timestamp_for_independent_confirmation(self):
        snapshot = {'state': 'filtered_empty', 'message': '待确认空清单', 'parcels': [], 'expectedCount': None, 'readAt': '2026-10-31T04:00:00.000Z'}
        self.write_snapshot(snapshot)
        with urlopen(self.url, timeout=3) as response:
            self.assertEqual(json.load(response), {**snapshot, 'expectedCount': 0})

    def test_invalid_empty_candidate_is_rejected(self):
        for extra in ({'parcels': [{'title': '残缺结果'}]}, {'expectedCount': 1}, {'readAt': ''}):
            self.write_snapshot({'state': 'filtered_empty', 'parcels': [], 'expectedCount': 0, 'readAt': '2026-10-31T04:00:00.000Z', **extra})
            with self.subTest(extra=extra), self.assertRaises(HTTPError) as caught:
                urlopen(self.url, timeout=3)
            self.assertEqual(caught.exception.code, 503)

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

    def test_damaged_snapshot_returns_service_error(self):
        for value in (None, [], 'invalid'):
            self.write_snapshot(value)
            with self.subTest(value=value), self.assertRaises(HTTPError) as caught:
                urlopen(self.url, timeout=3)
            self.assertEqual(caught.exception.code, 503)

    def test_private_files_and_directory_lists_are_not_exposed(self):
        self.write_snapshot({'state': 'ready', 'parcels': []})
        for path in ('/.private/official-snapshot.json', '/preview/../.private/official-snapshot.json', '/preview/%2e%2e/.private/official-snapshot.json', '/preview/'):
            with self.subTest(path=path), self.assertRaises(HTTPError) as caught:
                urlopen(self.url.replace('/api/official-snapshot', path), timeout=3)
            self.assertEqual(caught.exception.code, 404)


if __name__ == '__main__':
    unittest.main()
