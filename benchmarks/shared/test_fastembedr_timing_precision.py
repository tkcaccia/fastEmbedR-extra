"""Prevent active fastEmbedR timing workers from silently widening inputs."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class TimingPrecisionTest(unittest.TestCase):
    def test_current_mac_and_hpc_workers_do_not_widen_fit_input(self):
        workers = (
            ROOT / "macos/main-535d071-20261107-v2/worker.R",
            ROOT / "linux/matched-main-535d071-20261107-v3/"
                   "matched_worker_scaling.R",
        )
        for worker in workers:
            with self.subTest(worker=str(worker)):
                source = worker.read_text()
                self.assertNotIn("float::dbl(", source)
                self.assertNotIn('storage.mode(x) <- "double"', source)
        hpc = workers[1].read_text()
        self.assertIn('!inherits(x, "float32")', hpc)
        self.assertIn('!inherits(scores, "float32")', hpc)
        self.assertIn('input_precision = "float32"', hpc)

    def test_general_fastembedr_runners_fail_closed_on_precision(self):
        shared = (ROOT / "shared/benchmark_reviewer_validation.R").read_text()
        resident = (ROOT / "linux/resident-one-case-20261103/worker.R").read_text()
        self.assertIn('as_float32_matrix(dataset_data$float$data)', shared)
        self.assertIn('!inherits(x_fast, "float32")', shared)
        self.assertIn('!inherits(input, "float32")', resident)
        self.assertIn('input_precision = "float32"', resident)


if __name__ == "__main__":
    unittest.main()
