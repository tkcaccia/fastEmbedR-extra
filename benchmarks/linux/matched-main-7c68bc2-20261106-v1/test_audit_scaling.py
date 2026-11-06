"""Reject altered scaling source and claimed CPU worker counts."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import test_audit_results_v2 as base_test
from plan_scaling import HERE, expand_cases, write_plan
from policy import load_jsonl

spec = importlib.util.spec_from_file_location("scaling_auditor",
                                               HERE / "audit_scaling.py")
auditor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auditor)


class ScalingAuditorTests(unittest.TestCase):
    def test_staged_plan_identity(self):
        source = load_jsonl(HERE / "cases.jsonl")
        routes = json.loads((HERE / "routes.json").read_text())
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "plan"
            expanded = expand_cases(source, routes)
            write_plan(target, expanded)
            cases = [case for group in expanded.values() for case in group]
            original = auditor.HERE
            auditor.HERE = target
            try:
                self.assertTrue(auditor.plan_identity(cases))
                with (target / "matched_worker.R").open("a") as output:
                    output.write("\n# altered after planning\n")
                self.assertFalse(auditor.plan_identity(cases))
            finally:
                auditor.HERE = original

    def test_effective_cores_are_required(self):
        fixture = base_test.RouteIdentityTest("test_valid_result")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.metrics["cores_effective"] = 4
        fixture.check()
        original = auditor.HERE
        auditor.HERE = base_test.auditor.HERE
        self.addCleanup(setattr, auditor, "HERE", original)
        arguments = (fixture.case, fixture.results,
                     {"1": ("COMPLETED", "0:0")}, "routes", "worker")
        self.assertEqual(auditor.inspect_case(*arguments)["status"],
                         "audited")
        fixture.metrics["cores_effective"] = 2
        fixture.check()
        self.assertIn("science_identity",
                      auditor.inspect_case(*arguments)["issues"])

    def test_terminal_failed_case_is_preserved(self):
        fixture = base_test.RouteIdentityTest("test_valid_result")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.provenance["status"] = "failed"
        fixture.provenance["exit_code"] = 1
        fixture.check()
        (fixture.folder / "metrics.json").unlink()
        original = auditor.HERE
        auditor.HERE = base_test.auditor.HERE
        self.addCleanup(setattr, auditor, "HERE", original)
        result = auditor.inspect_case(
            fixture.case, fixture.results,
            {"1": ("FAILED", "1:0")}, "routes", "worker")
        self.assertEqual(result["status"], "failed_case")
        self.assertEqual(result["exit_code"], 1)


if __name__ == "__main__":
    unittest.main()
