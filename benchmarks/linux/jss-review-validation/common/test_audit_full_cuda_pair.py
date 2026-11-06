"""A failed comparator is recorded without hiding a complete fit output."""

import csv
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import audit_full_cuda_pair as audit_module


def write_row(path, row):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=row)
        writer.writeheader()
        writer.writerow(row)


class ComparatorAuditTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.campaign = root / "campaign"
        self.campaign.mkdir()
        self.inputs = root / "inputs"
        self.outputs = root / "outputs"
        self.method = (self.outputs / "workflow_comparators" /
                       "python_cuda" / "fixture" / "cuml_tsne")
        write_row(self.inputs / "fixture" / "manifest.csv", {
            "source_n": "10", "benchmark_n": "10", "full_source": "TRUE",
        })
        write_row(self.method / "status.csv", {
            "status": "invalid_fitted_kl",
        })
        write_row(self.method / "result_with_quality.csv", {
            "n": "10", "quality_analysis": "posthoc_R",
            "fitted_kl_status": "invalid", "n_neighbors": "90",
            "fitted_kl_divergence": "0", "sampled_kl": "2.2",
            "cuml_tsne_reported_neighbors": "90",
            "affinity_support": "cuml_default_90",
            "cuml_tsne_min_observed_iterations": "1000",
            "elapsed_median_sec": "2", "trustworthiness": "0.8",
            "preserve_at_30": "0.8",
            "neighborhood_quality_score": "0.8",
            "timing_eligible": "False",
        })
        write_row(self.method / "timing_repetitions.csv", {
            "observed_iterations": "1000",
        })
        (self.method / "embedding.csv.gz").write_bytes(b"data")
        (self.method / "quality.csv").write_text("quality\n")
        for family in ("tsne", "umap"):
            panel = (self.outputs / "cuda_comparison_live" / "fixture" /
                     family)
            panel.mkdir(parents=True)
            (panel / "comparison.png").write_bytes(b"png")
        (self.campaign / "failures.tsv").write_text("task\tstate\n")

    def test_invalid_kl_is_warning_and_never_pass(self):
        with patch.object(audit_module, "DATASETS", ("fixture",)), \
                patch.object(audit_module, "METHODS",
                             (("python_cuda", "cuml_tsne"),)), \
                patch.dict(os.environ, {"INCLUDE_NOMAD": "FALSE"}):
            self.assertTrue(audit_module.audit(
                self.campaign, self.inputs, self.outputs))
        report = (self.campaign / "final_audit.txt").read_text()
        self.assertTrue(report.startswith("WARN\n"))
        self.assertIn("native fitted KL is zero", report)

    def test_zero_native_kl_requires_independent_quality(self):
        result = self.method / "result_with_quality.csv"
        with result.open(newline="") as stream:
            row = next(csv.DictReader(stream))
        row["sampled_kl"] = "0"
        write_row(result, row)
        with patch.object(audit_module, "DATASETS", ("fixture",)), \
                patch.object(audit_module, "METHODS",
                             (("python_cuda", "cuml_tsne"),)), \
                patch.dict(os.environ, {"INCLUDE_NOMAD": "FALSE"}):
            self.assertFalse(audit_module.audit(
                self.campaign, self.inputs, self.outputs))
        report = (self.campaign / "final_audit.txt").read_text()
        self.assertIn("independent sampled KL is invalid", report)

    def test_unrecorded_fit_failure_is_error(self):
        write_row(self.method / "status.csv", {"status": "failed"})
        with patch.object(audit_module, "DATASETS", ("fixture",)), \
                patch.object(audit_module, "METHODS",
                             (("python_cuda", "cuml_tsne"),)), \
                patch.dict(os.environ, {"INCLUDE_NOMAD": "FALSE"}):
            self.assertFalse(audit_module.audit(
                self.campaign, self.inputs, self.outputs))
        self.assertTrue((self.campaign / "final_audit.txt").read_text()
                        .startswith("FAIL\n"))


if __name__ == "__main__":
    unittest.main()
