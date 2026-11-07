"""The capability gate must distinguish complete structure from proof."""

import csv
import tempfile
import unittest
from pathlib import Path

from benchmarks.shared.audit_capability_matrix import audit


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "benchmarks/capability-matrix-20261105.csv"


class CapabilityMatrixAuditTest(unittest.TestCase):
    def test_interim_grid_is_complete_but_not_final(self):
        interim = audit(SOURCE, ROOT)
        self.assertEqual(interim["rows"], 140)
        self.assertEqual(interim["errors"], [])
        final = audit(SOURCE, ROOT, final=True)
        self.assertEqual(len(final["errors"]), 138)
        self.assertTrue(all("still unqualified" in issue
                            for issue in final["errors"]))

    def test_duplicate_and_missing_evidence_fail(self):
        with SOURCE.open(newline="") as stream:
            rows = list(csv.DictReader(stream))
            fields = list(rows[0])
        rows[0] = dict(rows[1])
        rows[0]["qualification_status"] = "verified"
        rows[0]["evidence"] = "missing-evidence.md"
        rows[0]["remaining_gate"] = ""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "matrix.csv"
            with path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=fields)
                writer.writeheader()
                writer.writerows(rows)
            errors = audit(path, ROOT)["errors"]
        self.assertTrue(any("duplicate combination" in x for x in errors))
        self.assertTrue(any("missing combination" in x for x in errors))
        self.assertTrue(any("invalid evidence" in x for x in errors))


if __name__ == "__main__":
    unittest.main()
