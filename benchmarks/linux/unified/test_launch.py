"""Login-side submission must not execute the benchmark itself."""

import csv
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SUITE = Path(__file__).resolve().parent


class UnifiedLaunchTest(unittest.TestCase):
    def stage_fixture(self, directory):
        base = Path(directory)
        suite = base / "benchmark_scripts/unified"
        suite.mkdir(parents=True)
        for name in ("stage_jss.sh", "launch_jss.sh"):
            shutil.copy2(SUITE / name, suite / name)
        slurm = base / "benchmark_scripts/jss-review-validation/slurm"
        slurm.mkdir(parents=True)
        for name in ("run_preflight_cpu.sh", "run_preflight_cuda.sh"):
            (slurm / name).write_text("#!/bin/bash\n")
        image = base / "singularity/fastembedr_cuda.sif"
        image.parent.mkdir()
        image.write_bytes(b"source-locked fixture")
        root = base / "fastEmbedR-results/unified/campaign"
        root.mkdir(parents=True)
        bin_dir = base / "bin"
        bin_dir.mkdir()
        submit = bin_dir / "sbatch"
        submit.write_text(
            "#!/bin/sh\n"
            "case \" $* \" in\n"
            "  *run_preflight_cuda.sh*)\n"
            "    if [ \"${TEST_BLOCK_GPU:-}\" = 1 ]; then\n"
            "      echo QOSMaxGRESPerUser >&2; exit 1\n"
            "    fi;;\n"
            "esac\n"
            "n=$(cat \"$FASTEMBEDR_BASE/counter\")\n"
            "n=$((n+1))\n"
            "printf '%s' \"$n\" > \"$FASTEMBEDR_BASE/counter\"\n"
            "printf '%s\\n' \"$*\" >> \"$FASTEMBEDR_BASE/sbatch_args\"\n"
            "printf '%s\\n' \"$n\"\n")
        submit.chmod(0o755)
        queue = bin_dir / "squeue"
        queue.write_text("#!/bin/sh\nprintf '2001\\n2002\\n'\n")
        queue.chmod(0o755)
        (base / "counter").write_text("1000")
        env = dict(os.environ, FASTEMBEDR_BASE=str(base),
                   FASTEMBEDR_IMAGE_SHA256=hashlib.sha256(
                       image.read_bytes()).hexdigest(),
                   PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
        return suite / "stage_jss.sh", root, env

    def test_jss_preflights_gate_independent_campaign_launchers(self):
        with tempfile.TemporaryDirectory() as directory:
            script, root, env = self.stage_fixture(directory)
            for _ in range(2):
                run = subprocess.run(["bash", str(script), str(root)],
                                     env=env, capture_output=True,
                                     text=True)
                self.assertEqual(run.returncode, 0, run.stderr)
            with (root / "jss_stage_jobs.tsv").open() as stream:
                jobs = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([job["role"] for job in jobs],
                             ["cpu", "cuda", "paired", "extended"])
            args = (Path(directory) / "sbatch_args").read_text()
            self.assertEqual(args.count("--dependency=afterok:1001:1002"),
                             2)

    def test_gpu_quota_defers_jss_without_resubmitting_cpu(self):
        supported = subprocess.run(
            ["bash", "-c", "type mapfile"], capture_output=True)
        if supported.returncode:
            self.skipTest("GPU quota simulation requires Bash 4 or newer")
        with tempfile.TemporaryDirectory() as directory:
            script, root, env = self.stage_fixture(directory)
            blocked = subprocess.run(
                ["bash", str(script), str(root)],
                env=dict(env, TEST_BLOCK_GPU="1"),
                capture_output=True, text=True)
            self.assertEqual(blocked.returncode, 0, blocked.stderr)
            with (root / "jss_stage_jobs.tsv").open() as stream:
                jobs = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([job["role"] for job in jobs],
                             ["cpu", "resume"])
            resumed = subprocess.run(["bash", str(script), str(root)],
                                     env=env, capture_output=True,
                                     text=True)
            self.assertEqual(resumed.returncode, 0, resumed.stderr)
            with (root / "jss_stage_jobs.tsv").open() as stream:
                jobs = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([job["role"] for job in jobs],
                             ["cpu", "resume", "cuda", "paired",
                              "extended"])

    def test_compute_launcher_refuses_login_execution(self):
        env = dict(os.environ)
        env.pop("SLURM_JOB_ID", None)
        run = subprocess.run(["bash", str(SUITE / "launch.sh")],
                             env=env, capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn("do not run containers on login", run.stderr)

    def test_login_helper_exports_quota_and_only_submits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            suite = root / "benchmark_scripts/unified"
            suite.mkdir(parents=True)
            (suite / "submit.sbatch").write_text("#!/bin/bash\n")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            submit = bin_dir / "sbatch"
            submit.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
            submit.chmod(0o755)
            env = dict(os.environ, FASTEMBEDR_BASE=str(root),
                       PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            for command in ("purequota", "myquota"):
                with self.subTest(command=command):
                    quota = bin_dir / command
                    quota.write_text(
                        "#!/bin/sh\necho '/scratch 2048GB 975GB 47%'\n")
                    quota.chmod(0o755)
                    run = subprocess.run(
                        ["bash", str(SUITE / "submit_from_login.sh")],
                        env=env, check=True, capture_output=True,
                        text=True)
                    self.assertIn(
                        "DEEP1B_QUOTA_FREE_BYTES=1073000000000",
                        run.stdout)
                    self.assertIn(str(suite / "submit.sbatch"),
                                  run.stdout)
                    quota.unlink()


if __name__ == "__main__":
    unittest.main()
