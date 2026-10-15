"""Exercise quota arithmetic and Slurm dependencies without submitting."""

import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

from submit_storage_budgeted import make_waves, submit_waves


class StorageBudgetedTest(unittest.TestCase):
    def test_cpu_submit_needs_clustering_reserve(self):
        script = Path(__file__).with_name("submit_storage_budgeted.py")
        result = subprocess.run(
            ["python3", str(script), "--submit", "--quota-free-bytes",
             "2000000000000"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("positive clustering reserve", result.stderr)

    def test_initial_submit_needs_late_failure_acknowledgment(self):
        script = Path(__file__).with_name("submit_storage_budgeted.py")
        result = subprocess.run(
            ["python3", str(script), "--submit", "--routes", "cuda",
             "--admission", "initial", "--quota-free-bytes",
             "2000000000000"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--accept-late-space-failure", result.stderr)

    def test_billion_graphs_run_in_separate_waves_at_two_tb(self):
        waves = make_waves(1_000_000_000,
                           ["cpu", "cuda", "cuda2"],
                           2_000_000_000_000, True)
        self.assertEqual(len(waves), 3)
        self.assertEqual(waves[0][0]["reserved_bytes"],
                         1_112_000_000_008)
        self.assertLess(max(sum(item["reserved_bytes"] for item in wave)
                            for wave in waves),
                        1_600_000_000_000)

    def test_initial_admission_can_start_but_is_not_completion_bound(self):
        waves = make_waves(1_000_000_000, ["cuda", "cuda2"],
                           1_050_000_000_000, True,
                           admission="initial")
        self.assertEqual(len(waves), 2)
        self.assertEqual(waves[0][0]["reserved_bytes"],
                         392_000_786_440)
        self.assertEqual(waves[0][0]["later_graph_bound_bytes"],
                         1_112_000_000_008)
        roomy = make_waves(1_000_000_000, ["cuda", "cuda2"],
                           2_000_000_000_000, True,
                           admission="initial")
        self.assertEqual(len(roomy), 2)

    def test_small_graphs_can_share_a_wave(self):
        waves = make_waves(1_000_000,
                           ["cpu", "cuda", "cuda2"],
                           5_000_000_000, False)
        self.assertEqual(len(waves), 2)
        self.assertEqual(len(waves[0]), 2)

    def test_one_run_must_fit_and_routes_must_be_unique(self):
        with self.assertRaisesRegex(ValueError, "needs"):
            make_waves(1_000_000_000, ["cpu"],
                       1_000_000_000_000, True)
        with self.assertRaisesRegex(ValueError, "distinct"):
            make_waves(1_000_000, ["cpu", "cpu"],
                       5_000_000_000, False)
        with self.assertRaisesRegex(ValueError, "needs"):
            make_waves(1_000_000_000, ["cpu"],
                       2_000_000_000_000, True,
                       cpu_reserve=488_000_000_000)

    @patch("submit_storage_budgeted.subprocess.run")
    @patch.dict("submit_storage_budgeted.os.environ", {"USER": "test"})
    def test_later_wave_waits_for_every_previous_job(self, run):
        class Result:
            def __init__(self, stdout):
                self.stdout = stdout
                self.stderr = ""

        run.side_effect = [Result(""),
                           Result("dataset\tbackend\tmode\trows\tjob\t"
                                  "campaign\n"
                                  "deep\tcpu\tfull\t1000000\t101\t/a\n"),
                           Result("dataset\tbackend\tmode\trows\tjob\t"
                                  "campaign\n"
                                  "deep\tcuda\tfull\t1000000\t102\t/b\n"),
                           Result("dataset\tbackend\tmode\trows\tjob\t"
                                  "campaign\n"
                                  "deep\tcuda\tfull\t1000000\t103\t/c\n")]
        waves = make_waves(1_000_000,
                           ["cpu", "cuda", "cuda2"],
                           5_000_000_000, False)
        result = submit_waves(waves, 1_000_000,
                              5_000_000_000, False, Path("/suite"))
        self.assertEqual([item["job"] for item in result],
                         ["101", "102", "103"])
        self.assertEqual(run.call_args_list[1].kwargs["env"][
            "DEEP1B_AFTER_JOB"], "")
        self.assertEqual(run.call_args_list[2].kwargs["env"][
            "DEEP1B_AFTER_JOB"], "")
        self.assertEqual(run.call_args_list[3].kwargs["env"][
            "DEEP1B_AFTER_JOB"], "101:102")


if __name__ == "__main__":
    unittest.main()
