"""Small fixtures for the read-only resident panel audit."""

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE = Path(__file__).with_name("audit_panel.py")
SPEC = importlib.util.spec_from_file_location("panel_audit", MODULE)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def write_json(path, value):
    path.write_text(json.dumps(value) + "\n")


class PanelAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "manifests").mkdir()
        (self.root / "results" / "case1").mkdir(parents=True)
        (self.root / "worker.R").write_text("worker\n")
        (self.root / "run_case.py").write_text("runner\n")
        self.case = {"case_id": "case1", "dataset": "COIL20",
                     "method": "UMAP", "backend": "metal", "seed": 4,
                     "repetition": 1, "dimensions": 2,
                     "expected_rows": 100, "expected_columns": 10,
                     "output_dir": str(self.root / "results" / "case1"),
                     "source_sha256": "a" * 64,
                     "dll_sha256": "b" * 64,
                     "input_sha256": "c" * 64}
        self.manifest = self.root / "manifests" / "case1.json"
        write_json(self.manifest, self.case)
        write_json(self.root / "plan-summary.json",
                   {"cases": 1, "queued": 1})
        (self.root / "queue.txt").write_text("case1.json\n")
        events = [{"event": "case_finished", "case_id": "case1",
                   "exit_code": 0, "cleanup_clear": True},
                  {"event": "completed", "cases": 1}]
        (self.root / "queue-status.jsonl").write_text(
            "".join(json.dumps(event) + "\n" for event in events))
        self.output = self.root / "results" / "case1"
        identity = {"case_sha256": hashlib.sha256(
            self.manifest.read_bytes()).hexdigest(),
            "source_sha256": self.case["source_sha256"],
            "dll_sha256": self.case["dll_sha256"],
            "input_sha256": self.case["input_sha256"],
            "worker_sha256": hashlib.sha256(b"worker\n").hexdigest(),
            "runner_sha256": hashlib.sha256(b"runner\n").hexdigest()}
        write_json(self.output / "provenance.json", identity)
        self.run = {**identity, "case_id": "case1",
                    "status": "completed", "exit_code": 0,
                    "timed_out": False, "cleanup_clear": True,
                    "peak_rss_bytes": 500000,
                    "swap_before": "used = 7.69M",
                    "swap_after": "used = 7.69M"}
        write_json(self.output / "run.json", self.run)
        self.metrics = {"case_id": "case1", "dataset": "COIL20",
                        "method": "UMAP", "backend": "metal",
                        "observed_backend": "metal", "seed": 4,
                        "repetition": 1, "dimensions": 2,
                        "storage_mode": "resident", "fit_scope": "full",
                        "n_rows": 100, "n_columns": 10,
                        "quality": {"trustworthiness": 0.9,
                                    "label_accuracy": 0.8},
                        "load_seconds": 1, "preprocess_seconds": 1,
                        "graph_seconds": 0, "fit_seconds": 2,
                        "quality_seconds": 1}
        write_json(self.output / "metrics.json", self.metrics)
        (self.output / "output.rds").write_bytes(b"result")

    def test_complete_case_passes(self):
        self.assertEqual(audit.audit(self.root)["status"], "passed")

    def test_missing_result_is_incomplete(self):
        (self.output / "run.json").unlink()
        self.assertEqual(audit.audit(self.root)["status"],
                         "incomplete")

    def test_fallback_and_cleanup_fail(self):
        self.metrics["observed_backend"] = "cpu"
        self.run["cleanup_clear"] = False
        write_json(self.output / "metrics.json", self.metrics)
        write_json(self.output / "run.json", self.run)
        report = audit.audit(self.root)
        self.assertEqual(report["status"], "failed")
        issues = {item["issue"] for item in report["problems"]}
        self.assertIn("backend_fallback", issues)
        self.assertIn("run_or_cleanup", issues)

    def test_source_mismatch_fails(self):
        self.run["source_sha256"] = "d" * 64
        write_json(self.output / "run.json", self.run)
        self.assertEqual(audit.audit(self.root)["status"], "failed")


if __name__ == "__main__":
    unittest.main()
