"""Fixtures for the versioned Mac panel continuation audit."""

import hashlib
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_continued_panel as continued
from test_audit_panel import PanelAuditTests, write_json


class ContinuedPanelAuditTests(PanelAuditTests):
    def test_original_complete_case_passes(self):
        (self.root / "queue-status.jsonl").write_text(
            json.dumps({"event": "case_finished", "case_id": "case1",
                        "index": 1, "status": "completed",
                        "exit_code": 0, "cleanup_clear": True}) + "\n" +
            json.dumps({"event": "completed", "cases": 1}) + "\n")
        report = continued.audit(self.root, [])
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["counts"], {"completed": 1})

    def test_versioned_deferral_is_distinct_from_failure(self):
        second = {**self.case, "case_id": "case2",
                  "output_dir": str(self.root / "results" / "case2")}
        write_json(self.root / "manifests" / "case2.json", second)
        write_json(self.root / "plan-summary.json",
                   {"cases": 2, "queued": 2})
        (self.root / "queue.txt").write_text(
            "case1.json\ncase2.json\n")
        (self.root / "queue-status.jsonl").write_text(
            json.dumps({"event": "case_finished", "case_id": "case1",
                        "index": 1, "status": "completed",
                        "exit_code": 0, "cleanup_clear": True}) + "\n" +
            json.dumps({"event": "stopped", "index": 1}) + "\n")
        directory = self.root / "resume-v1"
        directory.mkdir()
        controller = directory / "resume_panel_v1.py"
        controller.write_text("versioned controller\n")
        history = [
            {"event": "started", "first_index": 2,
             "controller_sha256": hashlib.sha256(
                 controller.read_bytes()).hexdigest(),
             "queue_sha256": continued.digest(self.root / "queue.txt")},
            {"event": "deferred", "case_id": "case2", "index": 2,
             "reason": "time_limit"}]
        (directory / "resume-status.jsonl").write_text(
            "".join(json.dumps(event) + "\n" for event in history))
        report = continued.audit(self.root, [directory])
        self.assertEqual(report["status"], "finished_with_failures")
        self.assertEqual(report["counts"],
                         {"completed": 1, "deferred": 1})
        self.assertEqual(report["deferred"], ["case2"])
        self.assertEqual(report["problems"], [])
        history[0]["controller_sha256"] = "0" * 64
        (directory / "resume-status.jsonl").write_text(
            "".join(json.dumps(event) + "\n" for event in history))
        self.assertEqual(continued.audit(self.root, [directory])["status"],
                         "audit_failed")


if __name__ == "__main__":
    unittest.main()
