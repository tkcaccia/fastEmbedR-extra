#!/usr/bin/env python3

import hashlib
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from validate_input import validate


class BigANNInputTest(unittest.TestCase):
    def test_completed_files_and_rejected_mismatches(self):
        for dataset, columns in (("deep", 3), ("turing", 4)):
            with self.subTest(dataset=dataset), tempfile.TemporaryDirectory() \
                    as directory:
                root = Path(directory)
                path = root / "base.5.fbin"
                data = struct.pack("<II", 5, columns) + bytes(5 * columns * 4)
                path.write_bytes(data)
                record = {"dataset": dataset, "rows": 5,
                          "columns": columns, "bytes": len(data),
                          "sha256": hashlib.sha256(data).hexdigest()}
                manifest = root / "manifest.json"
                manifest.write_text(json.dumps(record))
                with patch("validate_input.ROWS", 5), patch.dict(
                        "validate_input.COLUMNS",
                        {"deep": 3, "turing": 4}, clear=True):
                    result = validate(path, True, dataset)
                    self.assertEqual(result["dataset"], dataset)
                    self.assertTrue(result["hash_verified_now"])
                    wrong = "turing" if dataset == "deep" else "deep"
                    with self.assertRaises(ValueError):
                        validate(path, dataset=wrong)
                    partial = root / "base.5.fbin.part"
                    partial.write_bytes(data)
                    with self.assertRaises(ValueError):
                        validate(partial, dataset=dataset)
                    record["dataset"] = wrong
                    manifest.write_text(json.dumps(record))
                    with self.assertRaises(ValueError):
                        validate(path, dataset=dataset)
                    record["dataset"] = dataset
                    record["sha256"] = "0" * 64
                    manifest.write_text(json.dumps(record))
                    with self.assertRaises(ValueError):
                        validate(path, True, dataset)


if __name__ == "__main__":
    unittest.main()
