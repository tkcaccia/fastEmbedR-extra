"""Pairing and metric checks for partial Mac CPU/Metal panels."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE = Path(__file__).with_name("summarize_paired.py")
SPEC = importlib.util.spec_from_file_location("paired_panel", MODULE)
paired = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(paired)


class PairedPanelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "results").mkdir()

    def add_case(self, name, backend, cores, seconds, trust,
                 status="completed"):
        result = self.root / "results" / name
        result.mkdir()
        run = {"status": status, "cleanup_clear": True,
               "peak_rss_bytes": 1000 * cores,
               "source_sha256": "a", "dll_sha256": "b",
               "input_sha256": "c"}
        metrics = {"dataset": "COIL20", "method": "UMAP",
                   "dimensions": 2, "seed": 4, "repetition": 1,
                   "backend": backend, "cores": cores,
                   "graph_seconds": 0, "fit_seconds": seconds,
                   "quality": {"trustworthiness": trust,
                               "label_accuracy": 0.7}}
        (result / "run.json").write_text(json.dumps(run))
        (result / "metrics.json").write_text(json.dumps(metrics))

    def test_pairs_both_cpu_lanes_to_same_metal_case(self):
        self.add_case("cpu1", "cpu", 1, 10, 0.90)
        self.add_case("cpu4", "cpu", 4, 4, 0.91)
        self.add_case("metal1", "metal", 1, 2, 0.89)
        report = paired.summarize(self.root)
        self.assertEqual(report["paired_comparisons"], 2)
        rows = {item["cpu_lane"]: item for item in report["pairs"]}
        self.assertEqual(rows["cpu1"]["fit_speedup_cpu_over_metal"], 5)
        self.assertAlmostEqual(rows["cpu1"][
            "quality_delta_metal_minus_cpu"]["trustworthiness"], -0.01)
        self.assertEqual(rows["cpu4"]["fit_speedup_cpu_over_metal"], 2)

    def test_failed_case_does_not_enter_pair(self):
        self.add_case("cpu1", "cpu", 1, 10, 0.9, status="failed")
        self.add_case("metal1", "metal", 1, 2, 0.89)
        report = paired.summarize(self.root)
        self.assertEqual(report["paired_comparisons"], 0)
        self.assertEqual(report["skipped"]["failed"], 1)

    def test_pca_singular_value_difference(self):
        result = paired.quality_delta(
            {"quality": {"singular_values": [10.0, 2.0]}},
            {"quality": {"singular_values": [10.0, 2.2]}}, "PCA")
        self.assertAlmostEqual(result["singular_relative_max"], 0.1)


if __name__ == "__main__":
    unittest.main()
