"""Small local checks; scientific jobs still need compute-node qualification."""

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from policy import DATA_FILES, validate_case
from run_case import verify_input_file
from audit_results import inspect_case


HERE = Path(__file__).resolve().parent


class InputIdentityTests(unittest.TestCase):
    def setUp(self):
        self.case = json.loads((HERE / "case.json").read_text())
        self.routes = json.loads((HERE / "routes.json").read_text())

    def test_shape_and_digest_are_mandatory(self):
        for field in ("expected_rows", "expected_columns", "input_sha256"):
            case = dict(self.case)
            case.pop(field)
            self.assertEqual(validate_case(case, self.routes)["status"],
                             "policy_rejected")
        for field, bad in (("expected_rows", 0),
                           ("expected_columns", False),
                           ("input_sha256", "invalid")):
            case = dict(self.case)
            case[field] = bad
            self.assertEqual(validate_case(case, self.routes)["status"],
                             "policy_rejected")

    def test_unreviewed_science_and_landmark_route_fail_closed(self):
        for field, value in (("n_neighbors", 31),
                             ("resolution", 2.0)):
            case = dict(self.case)
            case[field] = value
            self.assertEqual(validate_case(case, self.routes)["status"],
                             "policy_rejected")
        case = dict(self.case)
        case["method"] = "t-SNE"
        case["route_id"] = "fastembedr_cpu_tsne"
        case["n_iter"] = 301
        self.assertEqual(validate_case(case, self.routes)["status"],
                         "policy_rejected")
        case = dict(self.case)
        case["route_id"] = "fastembedr_cpu_umap_landmark"
        case["fit_scope"] = "landmark_fit_plus_projection"
        case["landmark_fraction"] = 0.5
        self.assertEqual(validate_case(case, self.routes)["status"],
                         "blocked_missing_in_memory_implementation")

    def test_exact_file_digest_and_mismatch(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / DATA_FILES["COIL20"]
            path.parent.mkdir(parents=True)
            path.write_bytes(b"resident fixture")
            self.case["input_sha256"] = hashlib.sha256(
                path.read_bytes()).hexdigest()
            self.assertEqual(verify_input_file(root, self.case)["status"],
                             "verified")
            path.write_bytes(b"changed fixture")
            self.assertEqual(verify_input_file(root, self.case)["status"],
                             "input_mismatch")

    def test_escape_and_missing_file_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "inputs"
            outside = Path(folder) / "outside.RData"
            outside.write_bytes(b"unreviewed")
            path = root / DATA_FILES["COIL20"]
            path.parent.mkdir(parents=True)
            self.assertEqual(verify_input_file(root, self.case)["status"],
                             "missing_input")
            path.symlink_to(outside)
            self.assertEqual(verify_input_file(root, self.case)["status"],
                             "missing_input")

    def test_auditor_keeps_missing_and_malformed_results_open(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertEqual(inspect_case(self.case, root, {}, "x", "y")
                             ["status"], "missing_result")
            result = root / self.case["case_id"]
            result.mkdir()
            (result / "provenance.json").write_text("not json")
            self.assertEqual(inspect_case(self.case, root, {}, "x", "y")
                             ["status"], "incomplete_result")
            (result / "provenance.json").write_text(json.dumps({
                "slurm_job_id": "123", "status": "started"}))
            self.assertEqual(inspect_case(
                self.case, root, {"123": ("RUNNING", "0:0")},
                "x", "y")["status"], "running")


if __name__ == "__main__":
    unittest.main()
