"""Safety checks for obsolete campaign cleanup."""

import json
import tempfile
import unittest
from pathlib import Path

import prune_comprehensive


class PruneComprehensiveTest(unittest.TestCase):
    def test_refuses_active_worker(self):
        with self.assertRaisesRegex(ValueError, "active jobs: 101"):
            prune_comprehensive.require_inactive({"100", "101"},
                                                 {"101", "999"})

    def test_collects_only_campaign_outputs_and_jobs(self):
        with tempfile.TemporaryDirectory() as tmp:
            results = Path(tmp) / "fastEmbedR-results/massive-data"
            root = results / "comprehensive/old"
            state_dir = root / "cpu/deep"
            state_dir.mkdir(parents=True)
            (root / "jobs.tsv").write_text(
                "lane\tdataset\tcontroller\tstate\n"
                "cpu\tdeep\t100\tstate.json\n")
            stage = results / "deep1b/stage"
            stage.mkdir(parents=True)
            (stage / "jobs.tsv").write_text(
                "kind\tjob_id\tcase_count\n"
                "cpu\t101\t2\n"
                "audit\t102\t1\n")
            visual = results / "full_layouts/plot"
            visual.mkdir(parents=True)
            (state_dir / "state.json").write_text(json.dumps({
                "pilot_controller": "103",
                "records": [{"campaign": str(stage),
                             "audit_job": "102",
                             "visual_output": str(visual),
                             "visual_job": "104"}]}))
            paths, jobs = prune_comprehensive.campaign_paths(root,
                                                               results)
            self.assertEqual(paths, {path.resolve() for path in
                                     (root, stage, visual)})
            self.assertEqual(jobs, {"100", "101", "102", "103", "104"})

    def test_rejects_path_outside_results(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            results = base / "fastEmbedR-results/massive-data"
            root = results / "comprehensive/old"
            state_dir = root / "cpu/deep"
            state_dir.mkdir(parents=True)
            (root / "jobs.tsv").write_text(
                "lane\tdataset\tcontroller\tstate\n"
                "cpu\tdeep\t100\tstate.json\n")
            (state_dir / "state.json").write_text(json.dumps({
                "records": [{"campaign": str(base / "Data/BigANN")}]}
            ))
            with self.assertRaisesRegex(ValueError, "Unexpected output"):
                prune_comprehensive.campaign_paths(root, results)


if __name__ == "__main__":
    unittest.main()
