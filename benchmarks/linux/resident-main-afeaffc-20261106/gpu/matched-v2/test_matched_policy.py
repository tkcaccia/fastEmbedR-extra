"""Fail-closed contract checks for the Mac-matched CUDA case."""

import importlib.util
import json
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "matched_gpu_policy", HERE / "policy.py")
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)
CASE = json.loads((HERE / "case.json").read_text())
ROUTES = json.loads((HERE / "gpu_routes.json").read_text())


class MatchedPolicyTests(unittest.TestCase):
    def test_reviewed_resident_case_is_eligible(self):
        self.assertEqual(policy.validate_case(CASE, ROUTES)["status"],
                         "eligible")

    def test_storage_identity_and_quality_controls_fail_closed(self):
        for change in ({"storage_mode": "file_backed"},
                       {"spill": True},
                       {"input_sha256": "bad"},
                       {"expected_rows": 0},
                       {"preprocessing_rank": 29},
                       {"quality_sample": 300}):
            with self.subTest(change=change):
                altered = {**CASE, **change}
                self.assertNotEqual(
                    policy.validate_case(altered, ROUTES)["status"],
                    "eligible")

    def test_unreviewed_method_or_gpu_count_is_blocked(self):
        for change in ({"method": "t-SNE"}, {"gpus": 3}):
            with self.subTest(change=change):
                altered = {**CASE, **change}
                self.assertNotEqual(
                    policy.validate_case(altered, ROUTES)["status"],
                    "eligible")


if __name__ == "__main__":
    unittest.main()
