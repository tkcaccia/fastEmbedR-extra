"""Verify that benchmark RAM evidence belongs to the current Slurm job."""

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("matched_v2", HERE / "run_case.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class CgroupMemoryTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.relative = Path(
            "system.slice/slurmstepd.scope/job_123/step_batch/user/task_0")
        self.folder = self.root / self.relative
        self.folder.mkdir(parents=True)
        self.proc = self.root / "proc_cgroup"
        self.proc.write_text(f"0::/{self.relative}\n")
        (self.folder / "memory.max").write_text("max\n")
        (self.folder / "memory.current").write_text("80000000\n")
        (self.folder / "memory.peak").write_text("120000000\n")
        self.env = {"SLURM_JOB_ID": "123", "SLURM_MEM_PER_NODE": "1024"}

    def test_accepts_scoped_peak_even_with_unlimited_task_counter(self):
        result = runner.job_cgroup_memory(self.proc, self.root, self.env)
        self.assertEqual(result["job_id"], "123")
        self.assertEqual(result["peak_bytes"], 120000000)
        self.assertIsNone(result["limit_bytes"])

    def test_rejects_another_job_or_root_cgroup(self):
        self.assertIsNone(runner.job_cgroup_memory(
            self.proc, self.root,
            {"SLURM_JOB_ID": "124", "SLURM_MEM_PER_NODE": "1024"}))
        self.proc.write_text("0::/\n")
        self.assertIsNone(runner.job_cgroup_memory(
            self.proc, self.root, self.env))

    def test_rejects_inconsistent_memory_values(self):
        (self.folder / "memory.current").write_text("130000000\n")
        self.assertIsNone(runner.job_cgroup_memory(
            self.proc, self.root, self.env))


if __name__ == "__main__":
    unittest.main()
