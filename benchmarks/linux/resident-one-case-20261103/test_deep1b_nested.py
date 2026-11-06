"""Verify nested Deep1B row selection without the large source file."""

import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

from prepare_deep1b_nested_10m import extract_nested


class Deep1BNestedTests(unittest.TestCase):
    def test_one_based_hundredth_rows_and_checksum(self):
        rows, columns = 120, 3
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.fbin"
            output = root / "selected.fbin"
            payload = struct.pack("<ii", rows, columns)
            for row in range(1, rows + 1):
                payload += struct.pack("<fff", float(row),
                                       float(row + 1000), float(-row))
            source.write_bytes(payload)
            digest = extract_nested(source, output, rows, columns, 30)
            selected = output.read_bytes()
            self.assertEqual(digest, hashlib.sha256(selected).hexdigest())
            self.assertEqual(struct.unpack("<ii", selected[:8]), (12, 3))
            values = struct.unpack("<" + "f" * 36, selected[8:])
            self.assertEqual([int(values[index])
                              for index in range(0, 36, 3)],
                             list(range(10, 121, 10)))
            self.assertEqual(len(selected), 8 + 12 * columns * 4)

    def test_corrupt_header_and_short_source_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.fbin"
            source.write_bytes(struct.pack("<ii", 10, 2))
            with self.assertRaisesRegex(ValueError, "header"):
                extract_nested(source, root / "wrong.fbin", 20, 2, 10)
            with self.assertRaisesRegex(ValueError, "ended early"):
                extract_nested(source, root / "short.fbin", 10, 2, 10)


if __name__ == "__main__":
    unittest.main()
