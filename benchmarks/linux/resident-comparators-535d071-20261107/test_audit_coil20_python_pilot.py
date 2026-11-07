import json
from pathlib import Path
import tempfile
import unittest

from audit_coil20_python_pilot import audit, METHODS, INPUT_SHA, IMAGE_SHA, PACKAGE_COMMIT


class PythonComparatorAuditTest(unittest.TestCase):
    def test_exact_roster_and_precision_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            worker = root / "coil20_python_worker.R"
            worker.write_text("fixture")
            import hashlib
            worker_sha = hashlib.sha256(worker.read_bytes()).hexdigest()
            accounting = []
            for index, method in enumerate(METHODS):
                job = str(8000 + index)
                accounting.append(f"123_{index}|{job}|COMPLETED|0:0")
                folder = root / "results" / f"coil20_{method}_cpu4_d2_s4"
                folder.mkdir(parents=True)
                (folder / "layout.rds").write_bytes(b"fixture")
                metrics = dict(dataset="COIL20", method=method,
                    backend="cpu", requested_cores=4,
                    seed=4, dimensions=2, n_rows=1440,
                    n_columns=16384, preprocessing_rank=30,
                    source_precision="float32",
                    comparator_precision="double",
                    input_sha256=INPUT_SHA, image_sha256=IMAGE_SHA,
                    package_commit=PACKAGE_COMMIT, worker_sha256=worker_sha,
                    output_file="layout.rds", slurm_job_id=job,
                    slurm_array_task_id=str(index),
                    comparator_version="test", load_seconds=1,
                    preprocess_seconds=1, conversion_seconds=0.1,
                    python_conversion_seconds=0.1,
                    parallel_note="four_requested_jobs",
                    fit_seconds=2, quality_seconds=1, write_seconds=0.1,
                    quality=dict(trustworthiness=0.9, label_accuracy=0.8))
                (folder / "metrics.json").write_text(json.dumps(metrics))
            source = "\n".join(accounting)
            self.assertEqual(audit(root, "123", source)["status"], "passed")
            path = root / "results/coil20_opentsne_cpu4_d2_s4/metrics.json"
            broken = json.loads(path.read_text())
            broken["source_precision"] = "double"
            path.write_text(json.dumps(broken))
            report = audit(root, "123", source)
            self.assertEqual(report["status"], "failed")
            self.assertIn("source_or_case_identity", report["cases"][0]["issues"])


if __name__ == "__main__":
    unittest.main()
