#!/usr/bin/env python3

import csv
import gzip
import tempfile
import unittest
from pathlib import Path

from audit_campaign import audit


def write_table(path, rows, delimiter=","):
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, rows[0], delimiter=delimiter)
        writer.writeheader()
        writer.writerows(rows)


class CampaignAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        case = {"case": "cpu_knn_20k", "phase": "pilot",
                "backend": "cpu", "mode": "knn", "rows": "20000"}
        write_table(self.root / "registry.tsv", [case], "\t")
        write_table(self.root / "cases_cpu.tsv", [case], "\t")
        write_table(self.root / "jobs.tsv",
                    [{"kind": "cpu", "job_id": "123", "case_count": "1"}],
                    "\t")
        (self.root / "launch.txt").write_text("phase=pilot\nlane=cpu\n")
        output = self.root / "results" / case["case"]
        output.mkdir(parents=True)
        write_table(output / "status.tsv", [{"exit_code": "0"}], "\t")
        self.metrics = {"status": "ok", "backend_requested": "cpu",
                        "backend_observed": "cpu", "knn_backend": "cpu",
                        "mode": "knn", "rows": "20000",
                        "first_row": "1",
                        "finite_sample": "TRUE", "elapsed_seconds": "1.2",
                        "rss_peak_bytes": "1000000", "output_bytes": "2400000",
                        "knn_recall_mean": "1", "knn_audit_rows": "1",
                        "hnsw_shard_count": "1",
                        "hnsw_m_effective": "32",
                        "hnsw_ef_construction_effective": "200",
                        "hnsw_ef_search_effective": "150",
                        "hnsw_tuning_rule_effective": "test"}
        self.metric_path = output / "metrics.csv"
        self.write_metrics()
        with gzip.open(output / "knn_audit_rows.csv.gz", "wt") as handle:
            writer = csv.DictWriter(handle, ("row", "recall"))
            writer.writeheader()
            writer.writerow(dict(row=10000, recall=1))
        with gzip.open(output / "hnsw_shards.csv.gz", "wt") as handle:
            writer = csv.DictWriter(handle, ("shard", "reference_rows",
                "m", "ef_construction", "ef_search", "tuning_rule"))
            writer.writeheader()
            writer.writerow(dict(shard=1, reference_rows=20000, m=32,
                ef_construction=200, ef_search=150, tuning_rule="test"))
        (output / "source_check.txt").write_text("image: OK\n")

    def write_metrics(self):
        write_table(self.metric_path, [self.metrics])

    def test_complete_cpu_knn_passes(self):
        report = audit(self.root)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["case_count"], 1)

    def test_wrong_backend_fails(self):
        self.metrics["backend_observed"] = "cuda"
        self.write_metrics()
        self.assertEqual(audit(self.root)["status"], "FAIL")

    def test_low_recall_is_visible(self):
        self.metrics["knn_recall_mean"] = "0.89"
        self.write_metrics()
        report = audit(self.root)
        self.assertEqual(report["status"], "FAIL")
        self.assertIn("0.89", report["failures"][0])

    def test_missing_effective_settings_fails(self):
        self.metrics["hnsw_ef_search_effective"] = ""
        self.write_metrics()
        self.assertEqual(audit(self.root)["status"], "FAIL")

    def test_wrong_row_window_fails(self):
        self.metrics["first_row"] = "1000001"
        self.write_metrics()
        self.assertEqual(audit(self.root)["status"], "FAIL")

    def test_missing_case_fails(self):
        (self.root / "cases_cpu.tsv").unlink()
        self.assertEqual(audit(self.root)["status"], "FAIL")

    def test_case_filter_matches_submitted_registry(self):
        with (self.root / "registry.tsv").open("a") as stream:
            stream.write("cpu_umap_20k\tpilot\tcpu\tumap\t20000\n")
        self.assertEqual(audit(self.root)["status"], "FAIL")
        (self.root / "launch.txt").write_text(
            "phase=pilot\nlane=cpu\ncase_filter=cpu_knn_20k\n")
        self.assertEqual(audit(self.root)["status"], "PASS")

    def test_missing_embedding_quality_fails(self):
        for filename in ("registry.tsv", "cases_cpu.tsv"):
            write_table(self.root / filename, [{
                "case": "cpu_knn_20k", "phase": "pilot",
                "backend": "cpu", "mode": "umap", "rows": "20000",
            }], "\t")
        self.metrics["mode"] = "umap"
        self.write_metrics()
        self.assertEqual(audit(self.root)["status"], "FAIL")

    def test_embedding_plot_and_quality_pass(self):
        for filename in ("registry.tsv", "cases_cpu.tsv"):
            write_table(self.root / filename, [{
                "case": "cpu_knn_20k", "phase": "pilot",
                "backend": "cpu", "mode": "umap", "rows": "20000",
            }], "\t")
        self.metrics["mode"] = "umap"
        self.write_metrics()
        output = self.root / "results" / "cpu_knn_20k"
        write_table(output / "quality.csv", [{
            "trustworthiness": "0.8", "knn_preservation_30": "0.5",
            "input_first_row": "1",
        }])
        with gzip.open(output / "plot_sample.csv.gz", "wt") as stream:
            writer = csv.DictWriter(stream, ("row_id", "dim1", "dim2"))
            writer.writeheader()
            writer.writerows({"row_id": i, "dim1": 1, "dim2": 2}
                             for i in range(1, 4097))
        with gzip.open(output / "plot_sample_10000.csv.gz", "wt") as stream:
            writer = csv.DictWriter(stream, ("row_id", "dim1", "dim2"))
            writer.writeheader()
            writer.writerows({"row_id": i, "dim1": 1, "dim2": 2}
                             for i in range(1, 10001))
        self.assertEqual(audit(self.root)["status"], "PASS")
        (output / "plot_sample_10000.csv.gz").unlink()
        self.assertEqual(audit(self.root)["status"], "FAIL")

    def test_cluster_requires_full_scan_and_sample(self):
        case = {"case": "cpu_knn_20k", "phase": "pilot",
                "backend": "cpu", "mode": "cluster", "rows": "20000",
                "cluster_method": "leiden"}
        for filename in ("registry.tsv", "cases_cpu.tsv"):
            write_table(self.root / filename, [case], "\t")
        self.metrics.update(mode="cluster", cluster_method="leiden")
        self.write_metrics()
        output = self.root / "results" / "cpu_knn_20k"
        write_table(output / "quality.csv", [{
            "scanned_rows": "20000", "input_first_row": "1",
            "landmarks_checked": "1000", "landmark_label_mismatches": "0",
            "communities": "2", "min_confidence": "0.2",
            "max_confidence": "1",
        }])
        with gzip.open(output / "cluster_sample.csv.gz", "wt") as stream:
            writer = csv.DictWriter(stream,
                                    ("row_id", "membership", "confidence"))
            writer.writeheader()
            writer.writerows({"row_id": i, "membership": 1,
                              "confidence": 0.8} for i in range(1, 513))
        self.assertEqual(audit(self.root)["status"], "PASS")
        self.metrics["cluster_method"] = "louvain"
        self.write_metrics()
        self.assertEqual(audit(self.root)["status"], "FAIL")

    def test_graph_requires_independent_holdout_recall(self):
        case = {"case": "cpu_knn_20k", "phase": "fresh5m_graph",
                "backend": "cpu", "mode": "knn", "rows": "20000"}
        for filename in ("registry.tsv", "cases_cpu.tsv"):
            write_table(self.root / filename, [case], "\t")
        (self.root / "launch.txt").write_text(
            "phase=fresh5m_graph\nlane=cpu\nfirst_row=1\n")
        self.assertEqual(audit(self.root)["status"], "FAIL")
        quality = [{"split": "tune", "query_count": "4096",
                    "lower95_recall": "0.999",
                    "fraction_below_099": "0.001"},
                   {"split": "holdout", "query_count": "4096",
                    "lower95_recall": "0.997",
                    "fraction_below_099": "0.005"}]
        path = self.root / "results" / "cpu_knn_20k" / "knn_exact_quality.csv"
        write_table(path, quality)
        self.assertEqual(audit(self.root)["status"], "PASS")
        quality[1]["lower95_recall"] = "0.98"
        write_table(path, quality)
        self.assertEqual(audit(self.root)["status"], "FAIL")

    def test_cuda_projection_cases_use_one_core(self):
        registry = Path(__file__).with_name("cases.tsv")
        with registry.open(newline="") as handle:
            cases = list(csv.DictReader(handle, delimiter="\t"))
        projections = [case for case in cases if
                       case["backend"] == "cuda" and
                       case["mode"] in ("umap", "tsne")]
        self.assertTrue(projections)
        self.assertTrue(all(case["cores"] == "1" for case in projections))

    def test_boundary_embedding_requires_full_row_png(self):
        case = {"case": "cpu_pca_100m", "phase": "boundary",
                "backend": "cpu", "mode": "pca", "rows": "100000000",
                "components": "2"}
        for filename in ("registry.tsv", "cases_cpu.tsv"):
            write_table(self.root / filename, [case], "\t")
        (self.root / "launch.txt").write_text(
            "phase=boundary\nlane=cpu\nfirst_row=1\n")
        self.assertIn("full-row PNG missing", " ".join(
            audit(self.root)["failures"]))

    def test_two_gpu_case_requires_two_observed_devices(self):
        (self.root / "launch.txt").write_text(
            "phase=pilot\nlane=cuda\nfirst_row=1\n")
        case = {"case": "cpu_knn_20k", "phase": "pilot",
                "backend": "cuda", "mode": "knn", "rows": "20000",
                "devices": "0,1"}
        for filename in ("registry.tsv", "cases_cpu.tsv"):
            write_table(self.root / filename, [case], "\t")
        self.metrics.update(backend_requested="cuda",
                            backend_observed="cuda", knn_backend="cuda")
        self.write_metrics()
        path = self.root / "results" / "cpu_knn_20k" / "gpu_memory.csv"
        write_table(path, [{"status": "ok", "peak_bytes": "100000",
                            "matched_samples": "2", "device_count": "1"}])
        self.assertEqual(audit(self.root)["status"], "FAIL")
        write_table(path, [{"status": "ok", "peak_bytes": "100000",
                            "matched_samples": "2", "device_count": "2"}])
        report = audit(self.root)
        self.assertEqual(report["status"], "PASS", report["failures"])


if __name__ == "__main__":
    unittest.main()
