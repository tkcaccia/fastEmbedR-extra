"""The GPU sampler must use job-local IDs and preserve physical identity."""

import csv
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("run_measured.sh")


class GpuMonitorTest(unittest.TestCase):
    def test_renumbered_slurm_gpu_is_measured_by_visible_id(self):
        bash4 = subprocess.run(
            ["bash", "-c", "declare -A values"], capture_output=True)
        if bash4.returncode:
            self.skipTest("GPU monitor needs Bash 4 or newer")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            monitor = bin_dir / "nvidia-smi"
            monitor.write_text(
                "#!/bin/sh\n"
                "[ \"$1\" = -i ] && [ \"$2\" = 0 ] || exit 5\n"
                "case \"$*\" in\n"
                "  *--query-gpu=memory.used*) echo 123;;\n"
                "  *--query-gpu=uuid*) echo GPU-test-uuid;;\n"
                "  *) exit 6;;\n"
                "esac\n")
            monitor.chmod(0o755)
            prefix = root / "measured"
            env = dict(os.environ, CUDA_VISIBLE_DEVICES="0",
                       SLURM_JOB_GPUS="2", FASTEMBEDR_TIME_BIN="disable",
                       PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            env.pop("SLURM_JOB_ID", None)
            result = subprocess.run(
                ["bash", str(SCRIPT), "cuda", str(prefix), "--",
                 "sleep", "0.2"], env=env, capture_output=True,
                text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            with Path(str(prefix) + ".gpu_identity.csv").open() as stream:
                identity = next(csv.DictReader(stream))
            self.assertEqual(identity, dict(gpu_id="0",
                                            nvml_id="0",
                                            slurm_physical_id="2",
                                            gpu_uuid="GPU-test-uuid"))
            with Path(str(prefix) + ".gpu_memory.csv").open() as stream:
                samples = list(csv.DictReader(stream))
            self.assertGreaterEqual(len(samples), 1)
            self.assertTrue(all(row["gpu_id"] == "0" for row in samples))

    def test_single_visible_nvml_gpu_resolves_renumbered_cuda_id(self):
        bash4 = subprocess.run(
            ["bash", "-c", "declare -A values"], capture_output=True)
        if bash4.returncode:
            self.skipTest("GPU monitor needs Bash 4 or newer")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            monitor = bin_dir / "nvidia-smi"
            monitor.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *--query-gpu=index*) echo 0;;\n"
                "  *--query-gpu=memory.used*)\n"
                "    [ \"$1\" = -i ] && [ \"$2\" = 0 ] || exit 5\n"
                "    echo 123;;\n"
                "  *--query-gpu=uuid*)\n"
                "    [ \"$1\" = -i ] && [ \"$2\" = 0 ] || exit 5\n"
                "    echo GPU-test-uuid;;\n"
                "  *) exit 6;;\n"
                "esac\n")
            monitor.chmod(0o755)
            prefix = root / "measured"
            env = dict(os.environ, CUDA_VISIBLE_DEVICES="2",
                       SLURM_JOB_GPUS="2", FASTEMBEDR_TIME_BIN="disable",
                       PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            env.pop("SLURM_JOB_ID", None)
            result = subprocess.run(
                ["bash", str(SCRIPT), "cuda", str(prefix), "--",
                 "sleep", "0.2"], env=env, capture_output=True,
                text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            with Path(str(prefix) + ".gpu_identity.csv").open() as stream:
                identity = next(csv.DictReader(stream))
            self.assertEqual(identity, dict(gpu_id="2", nvml_id="0",
                                            slurm_physical_id="2",
                                            gpu_uuid="GPU-test-uuid"))

    def test_multiple_visible_nvml_gpus_do_not_guess_identity(self):
        bash4 = subprocess.run(
            ["bash", "-c", "declare -A values"], capture_output=True)
        if bash4.returncode:
            self.skipTest("GPU monitor needs Bash 4 or newer")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            monitor = bin_dir / "nvidia-smi"
            monitor.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *--query-gpu=index*) printf '0\\n1\\n';;\n"
                "  *) exit 5;;\n"
                "esac\n")
            monitor.chmod(0o755)
            prefix = root / "measured"
            env = dict(os.environ, CUDA_VISIBLE_DEVICES="2,3",
                       SLURM_JOB_GPUS="2,3",
                       PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(
                ["bash", str(SCRIPT), "cuda", str(prefix), "--",
                 "true"], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Invalid GPU memory baseline", result.stderr)
            self.assertFalse(Path(str(prefix) + ".gpu_memory.csv").exists())


if __name__ == "__main__":
    unittest.main()
