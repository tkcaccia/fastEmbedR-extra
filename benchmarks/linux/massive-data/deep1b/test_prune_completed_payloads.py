#!/usr/bin/env python3
"""Safety checks for pruning audited benchmark payloads."""

import csv
import json
import tempfile
import unittest
from pathlib import Path

from prune_completed_payloads import completed_files, prune


class PruneCompletedPayloadsTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name)
        results = self.base / "fastEmbedR-results/massive-data"
        self.root = results / "comprehensive/run_1"
        self.campaign = results / "deep1b/stage_1"
        self.case = self.campaign / "results/cpu_pca_20k"
        self.case.mkdir(parents=True)
        (self.campaign / "audit.json").write_text(
            json.dumps({"status": "PASS"}))
        (self.campaign / "jobs.tsv").write_text(
            "kind\tjob_id\tcase_count\n"
            "cpu\t12345\t1\naudit\t12346\t1\n")
        (self.campaign / "cases_cpu.tsv").write_text(
            "case\tmode\tcomponents\n"
            "cpu_pca_20k\tpca\t2\n")
        self.payload = self.case / "output.f32"
        self.payload.write_bytes(b"12345678")
        (self.case / "metrics.csv").write_text("status\nok\n")
        self.output = results / "full_layouts/plot_1/deep"
        self.output.mkdir(parents=True)
        (self.output / "cpu_pca_20k.png").write_bytes(b"PNG")
        with (self.output / "visual_manifest.csv").open(
                "w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("case", "view", "rows", "plotted_rows",
                             "color_semantics", "image"))
            writer.writerow(("cpu_pca_20k", "xy", "2e+04", "20000",
                             "none", "cpu_pca_20k.png"))
        lane = self.root / "cpu/deep"
        lane.mkdir(parents=True)
        self.state = lane / "state.json"
        self.record = {"phase": "pilot", "repeat": 1,
                       "dataset": "deep", "campaign": str(self.campaign),
                       "audit_job": "12346", "visual_job": "12347",
                       "visual_output": str(self.output.parent)}
        self.save_record()

    def save_record(self):
        self.state.write_text(json.dumps({"records": [self.record]}))

    def test_dry_run_and_apply_keep_evidence(self):
        files, skipped = completed_files(self.root, self.base, set())
        self.assertEqual(files, [(self.payload, 8)])
        self.assertEqual(skipped, [])
        prune(self.root, self.base, set())
        self.assertTrue(self.payload.exists())
        prune(self.root, self.base, set(), apply=True)
        self.assertFalse(self.payload.exists())
        self.assertTrue((self.case / "metrics.csv").exists())
        self.assertTrue((self.output / "cpu_pca_20k.png").exists())
        self.assertTrue((self.root / "pruned_payloads.tsv").exists())

    def test_active_or_incomplete_plot_is_not_pruned(self):
        files, skipped = completed_files(self.root, self.base, {"12347"})
        self.assertEqual(files, [])
        self.assertEqual(skipped[0][1], "stage or plot job active")
        (self.output / "visual_manifest.csv").unlink()
        files, skipped = completed_files(self.root, self.base, set())
        self.assertEqual(files, [])
        self.assertEqual(skipped[0][1], "full-row figures incomplete")

    def test_failed_stage_or_missing_case_view_is_not_pruned(self):
        (self.campaign / "audit.json").write_text(
            json.dumps({"status": "FAIL"}))
        files, skipped = completed_files(self.root, self.base, set())
        self.assertEqual(files, [])
        self.assertEqual(skipped[0][1], "stage audit not PASS")
        (self.campaign / "audit.json").write_text(
            json.dumps({"status": "PASS"}))
        with (self.campaign / "cases_cpu.tsv").open("a") as stream:
            stream.write("cpu_tsne_20k\ttsne\t2\n")
        files, skipped = completed_files(self.root, self.base, set())
        self.assertEqual(files, [])
        self.assertEqual(skipped[0][1], "full-row figures incomplete")

    def test_rejects_unexpected_stage_path(self):
        self.record["campaign"] = str(self.base / "Data/BigANN/deep")
        self.save_record()
        with self.assertRaisesRegex(ValueError, "Unexpected stage path"):
            completed_files(self.root, self.base, set())


if __name__ == "__main__":
    unittest.main()
