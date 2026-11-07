"""Resume admission must preserve success and stop on ambiguous output."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "resume_queue", HERE / "resume_queue.py")
resume = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resume)


class ResumeAdmissionTest(unittest.TestCase):
    def test_completed_timeout_and_ambiguous_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            resume.STEFANO = Path(temporary)
            resume.ROOT_NAME = "panel"
            root = Path(temporary) / "panel"
            (root / "manifests").mkdir(parents=True)
            (root / "results").mkdir()
            (root / "plan-summary.json").write_text(
                json.dumps({"cases": 693, "queued": 693,
                            "package_commit": resume.PACKAGE_COMMIT,
                            "storage_mode": "resident", "fit_scope": "full",
                            "source_sha256": "source", "dll_sha256": "dll"}))
            names = ["case_0", resume.LIMITED_CASE] + [
                f"case_{i}" for i in range(2, 693)]
            (root / "queue.txt").write_text("\n".join(
                name + ".json" for name in names) + "\n")
            for name in names:
                (root / "manifests" / (name + ".json")).write_text(
                    json.dumps({"case_id": name,
                                "output_dir": str(root / "results" / name),
                                "source_sha256": "source",
                                "dll_sha256": "dll",
                                "storage_mode": "resident",
                                "fit_scope": "full",
                                "backend": "cpu", "spill": False}))
            done = root / "results" / names[0]
            done.mkdir()
            (done / "run.json").write_text(json.dumps({
                "case_id": names[0], "status": "completed",
                "cleanup_clear": True}))
            (done / "metrics.json").write_text("{}")
            limited = root / "results" / names[1]
            limited.mkdir()
            (limited / "run.json").write_text(
                json.dumps({"case_id": names[1], "timed_out": True}))
            self.assertEqual(resume.preflight(root), {
                "completed": 1, "resource_limited": 1, "pending": 691})
            (root / "results" / names[2]).mkdir()
            with self.assertRaisesRegex(ValueError, "unreviewed"):
                resume.preflight(root)


if __name__ == "__main__":
    unittest.main()
