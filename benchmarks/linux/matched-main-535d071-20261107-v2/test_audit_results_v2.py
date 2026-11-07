"""Check that the terminal auditor rejects changed route metadata."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("auditor", HERE / "audit_results_v2.py")
auditor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auditor)


class RouteIdentityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.original_here = auditor.HERE
        auditor.HERE = root
        self.addCleanup(setattr, auditor, "HERE", self.original_here)
        self.case = dict(case_id="fixture", dataset="COIL20", method="PCA",
                         expected_rows=100, expected_columns=10,
                         dimensions=2, cores=4, seed=4,
                         input_sha256="a" * 64,
                         fit_scope="all_rows_optimized",
                         storage_mode="in_memory", backend="cpu")
        (root / "cases").mkdir()
        (root / "cases" / "fixture.json").write_text(json.dumps(self.case))
        (root / "case.json").write_text(json.dumps(self.case))
        self.results = root / "results"
        folder = self.results / "fixture"
        folder.mkdir(parents=True)
        self.folder = folder
        self.provenance = dict(case_sha256=auditor.sha256(
            root / "cases" / "fixture.json"), routes_sha256="routes",
            worker_sha256="worker", package_commit=auditor.PACKAGE_COMMIT,
            status="completed", exit_code=0, slurm_job_id="1")
        self.identity = dict(status="verified", actual_sha256="a" * 64,
                             expected_sha256="a" * 64, size_bytes=100,
                             verification_seconds=0.01)
        self.memory = dict(scope="slurm_job_cgroup", peak_ram_bytes=1000,
                           after=dict(job_id="1"))
        self.metrics = dict(case_id="fixture", dataset="COIL20",
                            method="PCA", n_rows=100, n_columns=10,
                            dimensions=2, cores=4, seed=4,
                            input_sha256="a" * 64, observed_backend="cpu",
                            package_version="0.1",
                            fit_scope="all_rows_optimized",
                            storage_mode="in_memory", backend="cpu",
                            preprocessing_rank=None, result_file="output.rds",
                            quality=dict(singular_values=[2.0, 1.0]))
        for field in ("load_seconds", "preprocess_seconds", "graph_seconds",
                      "fit_seconds", "quality_seconds", "write_seconds"):
            self.metrics[field] = 0.01
        (folder / "output.rds").write_bytes(b"fixture")

    def check(self):
        for name, filename in (("provenance", "provenance.json"),
                               ("identity", "input_identity.json"),
                               ("memory", "memory.json"),
                               ("metrics", "metrics.json")):
            (self.folder / filename).write_text(
                json.dumps(getattr(self, name)))
        return auditor.inspect_case(self.case, self.results,
                                    {"1": ("COMPLETED", "0:0")},
                                    "routes", "worker")

    def test_valid_result(self):
        self.assertEqual(self.check()["status"], "audited")

    def test_route_tampering_fails(self):
        for field, value in (("seed", 9), ("storage_mode", "file_backed"),
                             ("fit_scope", "landmark_fit_plus_projection"),
                             ("backend", "cuda"),
                             ("package_version", "0.2"),
                             ("preprocessing_rank", 30),
                             ("result_file", "other.rds")):
            with self.subTest(field=field):
                original = self.metrics[field]
                self.metrics[field] = value
                self.assertIn("route_identity", self.check()["issues"])
                self.metrics[field] = original


if __name__ == "__main__":
    unittest.main()
