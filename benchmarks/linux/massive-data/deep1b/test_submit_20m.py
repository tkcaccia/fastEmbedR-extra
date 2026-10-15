"""Check the independent 20M campaign before any Slurm submission."""

import csv
import io
import os
import subprocess
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("submit_20m.sh")
FULL_SCRIPT = SCRIPT.with_name("submit_fullgraph5m.sh")


class Submit20mPlanTest(unittest.TestCase):
    def test_classic_two_gpu_request_is_rejected_before_submission(self):
        env = dict(os.environ, DEEP1B_FIT_MODE="classic",
                   DEEP1B_BACKEND_FILTER="cuda",
                   DEEP1B_GPU_DEVICES="0,1")
        result = subprocess.run(["bash", str(FULL_SCRIPT), "deep"],
                                text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, 2)
        self.assertIn("classic route", result.stderr)

    def test_four_gpu_request_passes_device_validation(self):
        env = dict(os.environ, DEEP1B_FIT_MODE="full",
                   DEEP1B_BACKEND_FILTER="cuda",
                   DEEP1B_GPU_DEVICES="0,1,2,3",
                   DEEP1B_IMAGE="/nonexistent/fastembedr.sif",
                   DEEP1B_QUOTA_FREE_BYTES="1000000000000")
        result = subprocess.run(["bash", str(FULL_SCRIPT), "deep"],
                                text=True, capture_output=True, env=env)
        self.assertNotIn("DEEP1B_GPU_DEVICES must", result.stderr)
        self.assertNotIn("Invalid CUDA device request", result.stderr)

    def test_sixteen_cpu_request_passes_core_validation(self):
        env = dict(os.environ, DEEP1B_FIT_MODE="full",
                   DEEP1B_BACKEND_FILTER="cpu",
                   DEEP1B_CPU_CORES="16",
                   DEEP1B_IMAGE="/nonexistent/fastembedr.sif",
                   DEEP1B_QUOTA_FREE_BYTES="1000000000000")
        result = subprocess.run(["bash", str(FULL_SCRIPT), "deep"],
                                text=True, capture_output=True, env=env)
        self.assertNotIn("DEEP1B_CPU_CORES must", result.stderr)

    def test_noncontiguous_gpu_request_is_rejected(self):
        env = dict(os.environ, DEEP1B_FIT_MODE="full",
                   DEEP1B_BACKEND_FILTER="cuda",
                   DEEP1B_GPU_DEVICES="0,2")
        result = subprocess.run(["bash", str(FULL_SCRIPT), "deep"],
                                text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, 2)
        self.assertIn("DEEP1B_GPU_DEVICES must", result.stderr)

    def test_plan_is_capped_and_has_distinct_capability_routes(self):
        output = subprocess.check_output(
            ["bash", str(SCRIPT), "--plan"], text=True)
        rows = list(csv.DictReader(io.StringIO(output), delimiter="\t"))
        self.assertEqual(len(rows), 18)
        self.assertEqual(max(int(row["rows"]) for row in rows),
                         20_000_000)
        for size in (1_000_000, 10_000_000, 20_000_000):
            cores = {int(row["cpu_cores"]) for row in rows
                     if row["mode"] == "full" and
                     row["backend"] == "cpu" and
                     int(row["rows"]) == size}
            self.assertEqual(cores, {1, 4, 8})
        classic = [row for row in rows if row["mode"] == "classic"]
        self.assertEqual({row["backend"] for row in classic},
                         {"cpu", "cuda"})
        two_gpu = [row for row in rows
                   if row["gpu_devices"] == "0,1"]
        self.assertEqual(len(two_gpu), 4)
        self.assertEqual({row["mode"] for row in two_gpu},
                         {"full", "pca"})
        self.assertEqual({int(row["rows"]) for row in two_gpu
                          if row["mode"] == "full"},
                         {1_000_000, 10_000_000, 20_000_000})
        self.assertEqual({row["backend"] for row in two_gpu},
                         {"cuda"})
        self.assertEqual(sum(int(row["required_bytes"])
                             for row in rows), 212_344_000_120)

        env = dict(os.environ, DEEP1B_REBUILD_KNN_FOR_UMAP="1")
        output = subprocess.check_output(
            ["bash", str(SCRIPT), "--plan"], text=True, env=env)
        rebuilt = list(csv.DictReader(io.StringIO(output), delimiter="\t"))
        self.assertEqual(len(rebuilt), len(rows))
        for shared, separate in zip(rows, rebuilt):
            self.assertEqual(shared["mode"], separate["mode"])
            self.assertEqual(shared["rows"], separate["rows"])
            difference = (240 * int(shared["rows"])
                          if shared["mode"] == "full" else 0)
            self.assertEqual(int(shared["required_bytes"]) -
                             int(separate["required_bytes"]), difference)


if __name__ == "__main__":
    unittest.main()
