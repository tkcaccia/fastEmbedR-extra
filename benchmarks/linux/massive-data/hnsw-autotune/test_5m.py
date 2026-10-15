"""Small source-lock and recall-gate checks for the 5M screen."""

import csv
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import audit_5m
import audit_refine
import make_cases_5m
import make_cases_refine
from audit import read_table


class FreshFiveMillionTest(unittest.TestCase):
    def test_refinement_uses_new_window_and_rejects_partial_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "refine"
            identity = {"path": "/dev/null", "sha256": "a" * 64,
                        "size_bytes": 400000000008,
                        "sha256_reverified_now": False}
            with patch.object(make_cases_refine, "validate_input",
                              return_value=identity):
                make_cases_refine.main(root, Path(directory))
            truth = read_table(root / "truth_cases.tsv", "\t")
            self.assertEqual({row["first_row"] for row in truth},
                             {"6000001"})
            self.assertEqual({row["scope"] for row in truth},
                             {"refine5m"})
            (root / "source.sha256").write_text("b" * 64 + "  image\n")
            self.assertFalse(audit_refine.audit(root))
            status = json.loads((root / "audit_refine.json").read_text())
            self.assertFalse(status["complete"])

    def test_cases_use_fresh_rows_and_bounded_grid(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "campaign"
            identity = {"path": "/dev/null", "sha256": "a" * 64,
                        "size_bytes": 400000000008,
                        "sha256_reverified_now": False}
            with patch.object(make_cases_5m, "validate_input",
                              return_value=identity):
                make_cases_5m.main(root, Path(directory))
            truth = read_table(root / "truth_cases.tsv", "\t")
            sweep = read_table(root / "sweep_cases.tsv", "\t")
            self.assertEqual(len(truth), 2)
            self.assertEqual(len(sweep), 3)
            self.assertEqual({row["first_row"] for row in truth},
                             {"1000001"})
            self.assertEqual({row["rows"] for row in sweep},
                             {"5000000"})
            self.assertEqual({row["k"] for row in sweep}, {"30"})
            self.assertEqual({row["query_count"] for row in truth},
                             {"8192"})
            (root / "source.sha256").write_text("b" * 64 + "  image\n")
            self.assertFalse(audit_5m.audit(root))
            status = json.loads((root / "audit_5m.json").read_text())
            self.assertFalse(status["complete"])
            self.assertEqual(status["cases_measured"], 0)

    def test_bootstrap_gate_distinguishes_misses(self):
        self.assertEqual(audit_5m.lower_bound([1.0] * 4096, 1), 1.0)
        self.assertLess(audit_5m.lower_bound([0.9] * 4096, 1), 0.99)

    def test_complete_source_locked_screen_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "campaign"
            identity = {"path": "/dev/null", "sha256": "a" * 64,
                        "size_bytes": 400000000008,
                        "sha256_reverified_now": False}
            with patch.object(make_cases_5m, "validate_input",
                              return_value=identity):
                make_cases_5m.main(root, Path(directory))
            (root / "source.sha256").write_text("b" * 64 + "  image\n")
            (root / "truth").mkdir()
            (root / "sweep").mkdir()
            for case in read_table(root / "truth_cases.tsv", "\t"):
                stem = case["dataset"] + "_fresh5m"
                for suffix in (".rds", "_geometry.csv", "_timing.csv"):
                    (root / "truth" / (stem + suffix)).write_text("evidence")
                (root / "truth" / (stem + "_timing.csv")).write_text(
                    "query_n,exact_seconds\n8192,1\n")
            for index, case in enumerate(read_table(
                    root / "sweep_cases.tsv", "\t")):
                rows = []
                for split in ("tune", "holdout"):
                    rows.append(dict(case, split=split, fit_rows="5000000",
                        image_sha256="b" * 64, faissr_version="0.99.52",
                        n_queries="4096", mean_recall="1",
                        p10_recall="1", min_recall="1",
                        boundary_tie_rows="0", build_seconds="2",
                        query_seconds="3", worker_elapsed_seconds="5",
                        rss_peak_bytes="1024", faissr_dll_sha256="c" * 64,
                        fastembedr_dll_sha256="d" * 64))
                name = f"case_{index:03d}"
                with (root / "sweep" / (name + ".csv")).open("w") as f:
                    writer = csv.DictWriter(f, fieldnames=rows[0])
                    writer.writeheader()
                    writer.writerows(rows)
                with (root / "sweep" / (name + "_queries.csv")).open(
                        "w") as f:
                    writer = csv.DictWriter(
                        f, fieldnames=("row", "split", "recall"))
                    writer.writeheader()
                    writer.writerows(dict(row=i, split="tune" if
                        i <= 4096 else "holdout", recall=1)
                        for i in range(1, 8193))
            self.assertTrue(audit_5m.audit(root))
            status = json.loads((root / "audit_5m.json").read_text())
            self.assertEqual(status["cases_measured"], 3)
            self.assertEqual(status["recall_passes"], 3)


if __name__ == "__main__":
    unittest.main()
