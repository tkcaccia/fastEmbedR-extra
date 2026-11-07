"""All GPU-capable submission entrypoints must fail closed."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


LINUX = Path(__file__).resolve().parents[1]

ENTRYPOINTS = (
    ("unified/submit.sbatch", ()),
    ("unified/submit_from_login.sh", ()),
    ("unified/start_jss_repair.sh", ()),
    ("unified/launch.sh", ()),
    ("unified/stage_jss.sh", ()),
    ("unified/launch_jss.sh", ()),
    ("massive-data/deep1b/submit_matrix.sh", ()),
    ("massive-data/deep1b/submit_fullgraph5m.sh", ()),
    ("massive-data/deep1b/submit_short_cuda_bundle.sh", ("deep",)),
    ("massive-data/deep1b/submit_retry_pca_2gpu.sh", ()),
    ("massive-data/deep1b/submit.sh", ()),
    ("massive-data/deep1b/submit_parallel.sh", ()),
    ("massive-data/deep1b/submit_automatic.sh", ()),
    ("massive-data/deep1b/submit_comprehensive.sh", ()),
    ("massive-data/deep1b/submit_extended.sh", ()),
    ("massive-data/deep1b/submit_20m.sh", ()),
    ("massive-data/deep1b/submit_deep_rebuild.sh", ()),
    ("jss-review-validation/submit_all.sh", ()),
    ("jss-review-validation/submit_preflight.sh", ()),
    ("jss-review-validation/submit_after_new_image.sh", ()),
    ("jss-review-validation/submit_recall_quality_compact.sh", ()),
    ("jss-review-validation/submit_3d.sh", ()),
    ("jss-review-validation/reviewer_closure/submit.sh", ("--submit",)),
    ("jss-review-validation/common/run_complete_campaign_controller.sh", ()),
    ("jss-review-validation/slurm/run_complete_campaign_controller_cpu1.sh", ()),
)

ARCHIVED_ENTRYPOINTS = (
    "submit_current_validation_hpc.sh",
    "run_current_cpu_validation_hpc.sh",
    "run_current_cuda_validation_hpc.sh",
    "jss-review-validation/slurm/run_3d_gpu_controller_cpu1.sh",
    "massive-data/visualization/submit_full_layouts.sh",
    "massive-data/visualization/slurm_full_layouts.sh",
    "unified/submit.sbatch",
    "unified/submit_from_login.sh",
    "unified/start_jss_repair.sh",
    "unified/launch.sh",
    "unified/stage_jss.sh",
    "unified/launch_jss.sh",
    "jss-review-validation/submit_complete_campaign.sh",
    "jss-review-validation/common/run_complete_campaign_controller.sh",
    "jss-review-validation/slurm/run_complete_campaign_controller_cpu1.sh",
    "jss-review-validation/file_backed/run_cases.sh",
    "massive-data/deep1b/submit_matrix.sh",
    "massive-data/real-data/case.sbatch",
)


class GpuPauseTest(unittest.TestCase):
    def test_gpu_capable_launchers_stop_before_submission(self):
        env = dict(os.environ)
        env.pop("FASTEMBEDR_HPC_GPU_PAUSED", None)
        for relative, args in ENTRYPOINTS:
            with self.subTest(script=relative):
                path = LINUX / relative
                if not path.exists():
                    continue
                result = subprocess.run(
                    ["bash", str(path), *args],
                    env=env, capture_output=True, text=True,
                    timeout=10)
                self.assertIn(result.returncode, (2, 78), result.stderr)
                self.assertTrue(
                    "GPU submissions remain paused" in result.stderr or
                    "policy_rejected" in result.stderr,
                    result.stderr)

    def test_archived_file_backed_launchers_reject_even_if_gpu_pause_lifts(
            self):
        with tempfile.TemporaryDirectory() as temporary:
            bin_dir = Path(temporary) / "bin"
            bin_dir.mkdir()
            sentinel = Path(temporary) / "submitted"
            fake = bin_dir / "sbatch"
            fake.write_text("#!/bin/sh\nprintf submitted > '" +
                            str(sentinel) + "'\n")
            fake.chmod(0o755)
            env = dict(os.environ, FASTEMBEDR_HPC_GPU_PAUSED="0",
                       PATH=str(bin_dir) + os.pathsep +
                       os.environ["PATH"])
            for relative in ARCHIVED_ENTRYPOINTS:
                with self.subTest(script=relative):
                    result = subprocess.run(
                        ["bash", str(LINUX / relative)], env=env,
                        capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 78,
                                     result.stderr)
                    self.assertIn("policy_rejected", result.stderr)
                    self.assertFalse(sentinel.exists())

    def test_archived_python_controllers_reject_before_submission(self):
        paths = (
            "massive-data/deep1b/controller.py",
            "massive-data/hnsw-autotune/followup_after_representative.py",
        )
        for relative in paths:
            with self.subTest(script=relative):
                result = subprocess.run(
                    ["python3", str(LINUX / relative)],
                    capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 78, result.stderr)
                self.assertIn("policy_rejected", result.stderr)

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript is unavailable")
    def test_direct_file_backed_r_worker_rejects_before_loading_data(self):
        worker = LINUX / "jss-review-validation/file_backed/run_case.R"
        result = subprocess.run(
            ["Rscript", str(worker), "unused", "/tmp", "/tmp"],
            capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("policy_rejected", result.stderr)


if __name__ == "__main__":
    unittest.main()
