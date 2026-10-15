"""Offline regression tests for the resumable BigANN downloader."""

import contextlib
import hashlib
import importlib.util
import io
import json
import struct
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "download_bigann_subset.py"
SPEC = importlib.util.spec_from_file_location("bigann_download", SCRIPT)
DOWNLOADER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DOWNLOADER)
FULL_DATA = struct.pack("<II20f", 10, 2, *range(20))


class RangeHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def headers_for(self, length):
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("ETag", self.server.etag)
        self.end_headers()

    def do_HEAD(self):
        self.send_response(200)
        self.headers_for(len(FULL_DATA))

    def do_GET(self):
        self.server.get_count += 1
        byte_range = self.headers.get("Range", "")
        if self.headers.get("If-Range") != self.server.etag:
            self.send_response(200)
            self.headers_for(len(FULL_DATA))
            self.wfile.write(FULL_DATA)
            return
        first, last = map(int, byte_range.removeprefix("bytes=").split("-"))
        block = FULL_DATA[first:last + 1]
        self.send_response(206)
        self.send_header(
            "Content-Range", f"bytes {first}-{last}/{len(FULL_DATA)}")
        self.headers_for(len(block))
        self.wfile.write(block)


class DownloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), RangeHandler)
        cls.thread = threading.Thread(
            target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.root = Path(self.scratch.name)
        self.server.etag = '"source-v1"'
        self.server.get_count = 0
        self.source = {
            "url": (f"http://127.0.0.1:{self.server.server_port}/base.fbin"),
            "columns": 2,
            "terms": "test terms",
        }

    def tearDown(self):
        self.scratch.cleanup()

    def invoke(self, preflight=False):
        argv = ["download_bigann_subset.py", "test", "--rows", "4",
                "--output-root", str(self.root), "--reserve-gb", "0"]
        if preflight:
            argv.append("--preflight-only")
        with (mock.patch.object(DOWNLOADER, "SOURCES", {"test": self.source}),
              mock.patch.object(DOWNLOADER, "TOTAL_ROWS", 10),
              mock.patch.object(sys, "argv", argv),
              contextlib.redirect_stdout(io.StringIO()) as output):
            DOWNLOADER.main()
        return output.getvalue()

    @property
    def paths(self):
        directory = self.root / "test" / "4"
        return (
            directory / "base.4.fbin",
            directory / "base.4.fbin.part",
            directory / "base.4.fbin.part.meta.json",
            directory / "manifest.json",
        )

    def test_download_and_verify_existing_file(self):
        self.assertIn("DONE", self.invoke())
        final, _partial, meta, manifest = self.paths
        self.assertEqual(final.read_bytes(),
                         struct.pack("<II", 4, 2) + FULL_DATA[8:40])
        record = json.loads(manifest.read_text())
        self.assertEqual(record["sha256"],
                         hashlib.sha256(final.read_bytes()).hexdigest())
        self.assertEqual(json.loads(meta.read_text())["source_etag"],
                         '"source-v1"')
        self.assertEqual(self.server.get_count, 1)
        self.assertIn("VERIFIED", self.invoke(preflight=True))
        self.assertEqual(self.server.get_count, 1)

    def test_resume_rejects_changed_source(self):
        _final, partial, meta, _manifest = self.paths
        partial.parent.mkdir(parents=True)
        partial.write_bytes(FULL_DATA[:16])
        identity = DOWNLOADER.source_identity(
            "test", self.source, 4, 2, 40, '"source-v1"')
        DOWNLOADER.write_json(meta, identity)
        self.server.etag = '"source-v2"'
        with self.assertRaisesRegex(RuntimeError, "identity has changed"):
            self.invoke()
        self.assertEqual(partial.stat().st_size, 16)
        self.assertEqual(self.server.get_count, 0)

    def test_resume_from_identified_partial(self):
        final, partial, meta, _manifest = self.paths
        partial.parent.mkdir(parents=True)
        partial.write_bytes(FULL_DATA[:16])
        identity = DOWNLOADER.source_identity(
            "test", self.source, 4, 2, 40, '"source-v1"')
        DOWNLOADER.write_json(meta, identity)
        self.assertIn("DONE", self.invoke())
        self.assertEqual(final.read_bytes(),
                         struct.pack("<II", 4, 2) + FULL_DATA[8:40])
        self.assertEqual(self.server.get_count, 2)

    def test_resume_repairs_corrupted_tail(self):
        final, partial, meta, _manifest = self.paths
        partial.parent.mkdir(parents=True)
        partial.write_bytes(FULL_DATA[:15] + b"\xff")
        identity = DOWNLOADER.source_identity(
            "test", self.source, 4, 2, 40, '"source-v1"')
        DOWNLOADER.write_json(meta, identity)
        self.assertIn("Rechecking partial tail", self.invoke())
        self.assertEqual(final.read_bytes(),
                         struct.pack("<II", 4, 2) + FULL_DATA[8:40])
        self.assertEqual(self.server.get_count, 2)

    def test_streaming_checkpoints_release_cached_pages(self):
        with (mock.patch.object(DOWNLOADER, "CHECKPOINT_BYTES", 16),
              mock.patch.object(DOWNLOADER, "drop_cache") as drop):
            self.invoke()
        self.assertGreaterEqual(drop.call_count, 2)

    def test_corrupted_completed_file_is_rejected(self):
        self.invoke()
        final, _partial, _meta, _manifest = self.paths
        with final.open("r+b") as output:
            output.seek(12)
            output.write(b"\xff")
        with self.assertRaisesRegex(RuntimeError, "manifest verification"):
            self.invoke()

    def test_concurrent_download_is_rejected(self):
        final, _partial, _meta, _manifest = self.paths
        final.parent.mkdir(parents=True)
        with DOWNLOADER.exclusive_download(final.parent):
            with self.assertRaisesRegex(RuntimeError, "Another download"):
                self.invoke()
        self.assertEqual(self.server.get_count, 0)

    def test_resume_rejects_unidentified_partial(self):
        _final, partial, _meta, _manifest = self.paths
        partial.parent.mkdir(parents=True)
        partial.write_bytes(FULL_DATA[:16])
        with self.assertRaisesRegex(RuntimeError, "no source identity"):
            self.invoke()

    def test_finalization_recovers_from_rename_crash(self):
        final, _partial, meta, manifest = self.paths
        final.parent.mkdir(parents=True)
        final.write_bytes(struct.pack("<II", 4, 2) + FULL_DATA[8:40])
        identity = DOWNLOADER.source_identity(
            "test", self.source, 4, 2, 40, '"source-v1"')
        DOWNLOADER.write_json(meta, identity)
        self.assertIn("VERIFIED", self.invoke())
        self.assertTrue(manifest.exists())
        self.assertIsNone(json.loads(manifest.read_text())["download_seconds"])

    def test_complete_file_without_provenance_is_rejected(self):
        final, _partial, _meta, _manifest = self.paths
        final.parent.mkdir(parents=True)
        final.write_bytes(struct.pack("<II", 4, 2) + FULL_DATA[8:40])
        with self.assertRaisesRegex(RuntimeError, "no manifest"):
            self.invoke()

    def test_if_range_prevents_mixed_download(self):
        self.server.etag = '"source-v2"'
        with mock.patch.object(DOWNLOADER, "inspect_remote",
                               return_value='"source-v1"'):
            with self.assertRaisesRegex(RuntimeError, "exact byte range"):
                self.invoke()
        final, partial, _meta, _manifest = self.paths
        self.assertFalse(final.exists())
        self.assertEqual(partial.stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
