"""Fail closed when the staged CPU4 pilot roster changes."""

import json
from pathlib import Path
import tempfile
import unittest

from audit_mass41_subset_v1 import selected_cases


HERE = Path(__file__).resolve().parent


class Mass41SubsetTests(unittest.TestCase):
    def setUp(self):
        self.cases = [json.loads(line) for line in
                      (HERE / "cases.jsonl").read_text().splitlines()]
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        wave = [case["case_id"] for case in self.cases
                if case["cores"] == 4]
        (self.root / "wave_cpu4.txt").write_text("\n".join(wave) + "\n")

    def test_exact_three_case_roster(self):
        rows = selected_cases(self.root, self.cases)
        self.assertEqual([index for index, _ in rows], [42, 43, 44])
        self.assertEqual([case["method"] for _, case in rows],
                         ["Leiden", "Louvain", "PCA"])

    def test_mismatched_case_is_rejected(self):
        wave = (self.root / "wave_cpu4.txt").read_text().splitlines()
        wave[43] = wave[42]
        (self.root / "wave_cpu4.txt").write_text("\n".join(wave) + "\n")
        with self.assertRaises(ValueError):
            selected_cases(self.root, self.cases)


if __name__ == "__main__":
    unittest.main()
