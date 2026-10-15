"""Check that payload accounting excludes linked images and input data."""

import tempfile
import unittest
from pathlib import Path

from disk_peak import payload_bytes


class DiskPeakTest(unittest.TestCase):
    def test_counts_only_fit_payload_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "work").mkdir()
            (root / "results").mkdir()
            (root / "image.sif").write_bytes(b"x" * 100)
            (root / "work" / "graph.bin").write_bytes(b"a" * 4)
            (root / "results" / "layout.f32").write_bytes(b"b" * 8)
            apparent, allocated = payload_bytes(root)
            self.assertEqual(apparent, 12)
            self.assertGreaterEqual(allocated, 12)


if __name__ == "__main__":
    unittest.main()
