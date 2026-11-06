"""A unified campaign passes only when every planned component passes."""

import csv
import tempfile
import unittest
from pathlib import Path

from audit import evaluate


def table(path, fieldnames, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames,
                                delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(records)


class UnifiedAuditTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "unified"
        self.root.mkdir()
        self.digest = "a" * 64
        (self.root / "image.sha256").write_text(self.digest + "  image.sif\n")
        self.children = {name: self.root / name for name in
                         ("jss_paired", "jss_extended", "deep1b_matrix")}
        table(self.root / "components.tsv", ("component", "path"),
              [dict(component=name, path=str(path / "jobs.tsv" if
                    name == "deep1b_matrix" else path)) for name, path in
               self.children.items()])
        table(self.root / "launch_status.tsv",
              ("campaign", "launch_exit_code", "log"),
              [dict(campaign=name, launch_exit_code="0", log="") for name in
               ("jss_staged", "deep1b")])
        for name in ("jss_paired", "jss_extended"):
            child = self.children[name]
            child.mkdir()
            (child / "launch_status.txt").write_text("status=SUBMITTED\n")
            (child / "campaign_manifest.txt").write_text(
                f"image_sha256={self.digest}\n")
            verdict = "PASS\n" if name == "jss_paired" else "status=PASS\n"
            (child / "final_audit.txt").write_text(verdict)
            table(child / "failures.tsv", ("task", "state"), [])
        matrix = self.children["deep1b_matrix"]
        matrix.mkdir()
        (matrix / "identity.txt").write_text(
            f"image_sha256={self.digest}\n")
        (matrix / "source.sha256").write_text("source lock\n")
        self.case = matrix / "case"
        self.case.mkdir()
        (self.case / "audit.json").write_text(
            '{"status":"PASS","warnings":[]}\n')
        case = dict(mode="full", rows="1000000", lane="cpu16",
                    job="123", campaign=str(self.case))
        table(matrix / "plan.tsv", ("mode", "rows", "lane"), [case])
        table(matrix / "jobs.tsv",
              ("mode", "rows", "lane", "job", "campaign"), [case])

    def test_all_three_components_must_pass(self):
        report = evaluate(self.root)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(len(report["cases"]), 1)

    def test_missing_planned_case_is_incomplete(self):
        table(self.children["deep1b_matrix"] / "jobs.tsv",
              ("mode", "rows", "lane", "job", "campaign"), [])
        self.assertEqual(evaluate(self.root)["status"], "INCOMPLETE")

    def test_jss_failure_cannot_be_masked_by_deep_pass(self):
        (self.children["jss_extended"] / "final_audit.txt").write_text(
            "status=FAIL\n")
        self.assertEqual(evaluate(self.root)["status"], "FAIL")

    def test_measured_comparator_failure_is_warning_not_pass(self):
        (self.children["jss_paired"] / "final_audit.txt").write_text(
            "WARN\nFlowRepository/cuML: fitted KL invalid\n")
        report = evaluate(self.root)
        self.assertEqual(report["status"], "WARN")
        self.assertEqual(report["components"]["jss_paired"]["status"],
                         "WARN")

    def test_recall_warning_is_not_final_pass(self):
        (self.case / "audit.json").write_text(
            '{"status":"PASS","warnings":["recall below 0.99"]}\n')
        self.assertEqual(evaluate(self.root)["status"], "WARN")

    def test_source_identity_mismatch_fails(self):
        (self.children["deep1b_matrix"] / "identity.txt").write_text(
            "image_sha256=changed\n")
        self.assertEqual(evaluate(self.root)["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
