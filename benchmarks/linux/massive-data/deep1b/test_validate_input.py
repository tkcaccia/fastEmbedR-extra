#!/usr/bin/env python3

import hashlib
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from validate_input import validate


class Deep1BInputTest(unittest.TestCase):
    def test_completed_file_and_rejected_partial(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "base.5.fbin"
            data = struct.pack("<II", 5, 3) + bytes(5 * 3 * 4)
            path.write_bytes(data)
            record = {"dataset": "deep", "rows": 5, "columns": 3,
                      "bytes": len(data),
                      "sha256": hashlib.sha256(data).hexdigest()}
            (root / "manifest.json").write_text(json.dumps(record))
            with patch("validate_input.ROWS", 5), patch(
                    "validate_input.COLUMNS", 3), patch(
                    "validate_input.BYTES", len(data)):
                self.assertTrue(validate(path, True)["hash_verified_now"])
                partial = root / "base.5.fbin.part"
                partial.write_bytes(data)
                with self.assertRaises(ValueError):
                    validate(partial)
                record["sha256"] = "0" * 64
                (root / "manifest.json").write_text(json.dumps(record))
                with self.assertRaises(ValueError):
                    validate(path, True)


if __name__ == "__main__":
    unittest.main()
