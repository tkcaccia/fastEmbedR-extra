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


@unittest.skip("Archived unified launcher rejects HPC submissions.")
class UnifiedLaunchTest(unittest.TestCase):
    def test_unified_launcher_records_all_three_components(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            suite = base / "benchmark_scripts"
            unified = suite / "unified"
            unified.mkdir(parents=True)
            for name in ("launch.sh", "submit.sbatch",
                         "submit_from_login.sh", "launch_jss.sh", "audit.py"):
                shutil.copy2(SUITE / name, unified / name)
            (unified / "stage_jss.sh").write_text(
                '#!/bin/bash\nprintf "%s\\n" "$FASTEMBEDR_IMAGE"\n')
            jss = suite / "jss-review-validation"
            (jss / "common").mkdir(parents=True)
            (jss / "submit_complete_campaign.sh").write_text("#!/bin/bash\n")
            matrix = suite / "massive-data/deep1b"
            matrix.mkdir(parents=True)
            (matrix / "submit_matrix.sh").write_text(
                '#!/bin/bash\n'
                'echo "Matrix ledger: '
                '$DEEP1B_BASE/fastEmbedR-results/matrix/jobs.tsv"\n')
            (base / "Data/BigANN/deep/1000000000").mkdir(
                parents=True)
            image = base / "singularity/candidate.sif"
            image.parent.mkdir()
            image.write_bytes(b"selected image")
            digest = hashlib.sha256(image.read_bytes()).hexdigest()
            (jss / "common/image_source_identity.csv").write_text(
                "image_sha256\n" + digest + "\n")
            env = dict(os.environ, FASTEMBEDR_BASE=str(base),
                       FASTEMBEDR_IMAGE=str(image),
                       FASTEMBEDR_IMAGE_SHA256=digest,
                       FASTEMBEDR_HPC_GPU_PAUSED="0",
                       DEEP1B_QUOTA_FREE_BYTES="1000000000",
                       SLURM_JOB_ID="123")
            run = subprocess.run(["bash", str(unified / "launch.sh")],
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            root = next((base / "fastEmbedR-results/unified").iterdir())
            with (root / "components.tsv").open() as stream:
                children = {row["component"]: row["path"] for row in
                            csv.DictReader(stream, delimiter="\t")}
            self.assertEqual(set(children), {"jss_paired", "jss_extended",
                                             "deep1b_matrix"})
            self.assertTrue(children["deep1b_matrix"].endswith("jobs.tsv"))
            self.assertIn(str(image),
                          (root / "jss_stage_launch.log").read_text())

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
        (slurm.parent / "verify_preflight.sh").write_text(
            "#!/bin/bash\nexit 0\n")
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
        accounting = bin_dir / "sacct"
        accounting.write_text(
            "#!/bin/sh\n"
            "while [ $# -gt 0 ]; do\n"
            "  if [ \"$1\" = -j ]; then job=$2; break; fi\n"
            "  shift\n"
            "done\n"
            "printf '%s|%s|0:0\\n' \"$job\" "
            "\"${TEST_PREFLIGHT_STATE:-PENDING}\"\n")
        accounting.chmod(0o755)
        (base / "counter").write_text("1000")
        env = dict(os.environ, FASTEMBEDR_BASE=str(base),
                   FASTEMBEDR_IMAGE_SHA256=hashlib.sha256(
                       image.read_bytes()).hexdigest(),
                   FASTEMBEDR_HPC_GPU_PAUSED="0",
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

    def test_paired_only_leaves_extended_unsubmitted(self):
        with tempfile.TemporaryDirectory() as directory:
            script, root, env = self.stage_fixture(directory)
            run = subprocess.run(
                ["bash", str(script), str(root)],
                env=dict(env, JSS_ROLES="paired"),
                capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            with (root / "jss_stage_jobs.tsv").open() as stream:
                jobs = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([job["role"] for job in jobs],
                             ["cpu", "cuda", "paired"])

    def test_completed_preflights_do_not_create_stale_dependency(self):
        with tempfile.TemporaryDirectory() as directory:
            script, root, env = self.stage_fixture(directory)
            paired = subprocess.run(
                ["bash", str(script), str(root)],
                env=dict(env, JSS_ROLES="paired"),
                capture_output=True, text=True)
            self.assertEqual(paired.returncode, 0, paired.stderr)
            for role in ("cpu", "cuda"):
                identity = root / "jss_preflight/identity" / role
                identity.mkdir(parents=True)
                (identity / "identity.csv").write_text(
                    "image_sha256,package_version\n"
                    f"{env['FASTEMBEDR_IMAGE_SHA256']},0.1\n")
            resumed = subprocess.run(
                ["bash", str(script), str(root)],
                env=dict(env, JSS_ROLES="extended",
                         TEST_PREFLIGHT_STATE="COMPLETED"),
                capture_output=True, text=True)
            self.assertEqual(resumed.returncode, 0, resumed.stderr)
            lines = (Path(directory) / "sbatch_args").read_text().splitlines()
            self.assertIn("launch_jss.sh", lines[-1])
            self.assertNotIn("--dependency=", lines[-1])
            with (root / "jss_stage_jobs.tsv").open() as stream:
                roles = [row["role"] for row in
                         csv.DictReader(stream, delimiter="\t")]
            self.assertEqual(roles, ["cpu", "cuda", "paired", "extended"])

    def test_jss_preflights_use_the_selected_image(self):
        with tempfile.TemporaryDirectory() as directory:
            script, root, env = self.stage_fixture(directory)
            candidate = Path(directory) / "singularity/candidate.sif"
            candidate.write_bytes(b"new image")
            env["FASTEMBEDR_IMAGE"] = str(candidate)
            env["FASTEMBEDR_IMAGE_SHA256"] = hashlib.sha256(
                candidate.read_bytes()).hexdigest()
            run = subprocess.run(["bash", str(script), str(root)],
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            args = (Path(directory) / "sbatch_args").read_text()
            self.assertIn(f"IMAGE={candidate}", args)

    def test_jss_stage_can_use_an_isolated_suite(self):
        with tempfile.TemporaryDirectory() as directory:
            _, root, env = self.stage_fixture(directory)
            isolated = Path(directory) / "benchmark_scripts_repair"
            unified = isolated / "unified"
            unified.mkdir(parents=True)
            for name in ("stage_jss.sh", "launch_jss.sh"):
                shutil.copy2(SUITE / name, unified / name)
            slurm = isolated / "jss-review-validation/slurm"
            slurm.mkdir(parents=True)
            for name in ("run_preflight_cpu.sh", "run_preflight_cuda.sh"):
                (slurm / name).write_text("#!/bin/bash\n")
            env["FASTEMBEDR_SUITE_ROOT"] = str(isolated)
            run = subprocess.run(
                ["bash", str(unified / "stage_jss.sh"), str(root)],
                env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            args = (Path(directory) / "sbatch_args").read_text()
            self.assertIn(str(slurm / "run_preflight_cpu.sh"), args)
            self.assertIn(str(unified / "launch_jss.sh"), args)

    def test_repair_launcher_locks_isolated_suite(self):
        with tempfile.TemporaryDirectory() as directory:
            _, _, env = self.stage_fixture(directory)
            isolated = Path(directory) / "benchmark_scripts_repair"
            unified = isolated / "unified"
            unified.mkdir(parents=True)
            for name in ("stage_jss.sh", "launch_jss.sh",
                         "start_jss_repair.sh"):
                shutil.copy2(SUITE / name, unified / name)
            jss = isolated / "jss-review-validation"
            slurm = jss / "slurm"
            slurm.mkdir(parents=True)
            for name in ("run_preflight_cpu.sh", "run_preflight_cuda.sh"):
                (slurm / name).write_text("#!/bin/bash\n")
            digest = hashlib.sha256(
                (slurm / "run_preflight_cpu.sh").read_bytes()).hexdigest()
            (jss / "FILES.sha256").write_text(
                f"{digest}  ./slurm/run_preflight_cpu.sh\n")
            env.update(FASTEMBEDR_SUITE_ROOT=str(isolated),
                       FASTEMBEDR_IMAGE=str(Path(directory) /
                                             "singularity/fastembedr_cuda.sif"))
            run = subprocess.run(
                ["bash", str(unified / "start_jss_repair.sh")],
                env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertIn("JSS repair root:", run.stdout)
            root = next((Path(directory) / "fastEmbedR-results/unified")
                        .glob("*_jssrepair_*"))
            self.assertTrue((root / "jss_suite.sha256").is_file())
            with (root / "jss_stage_jobs.tsv").open() as stream:
                jobs = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([job["role"] for job in jobs],
                             ["cpu", "cuda", "paired", "extended"])

    def test_jss_resume_rejects_changed_launcher_source(self):
        with tempfile.TemporaryDirectory() as directory:
            script, root, env = self.stage_fixture(directory)
            first = subprocess.run(["bash", str(script), str(root)],
                                   env=env, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            launcher = script.with_name("launch_jss.sh")
            launcher.write_text(launcher.read_text() + "\n# changed\n")
            retry = subprocess.run(["bash", str(script), str(root)],
                                   env=env, capture_output=True, text=True)
            self.assertEqual(retry.returncode, 3)
            self.assertIn("source changed", retry.stderr)

    def test_gpu_quota_stops_jss_without_deferred_retry(self):
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
            self.assertEqual(blocked.returncode, 3, blocked.stderr)
            with (root / "jss_stage_jobs.tsv").open() as stream:
                jobs = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([job["role"] for job in jobs],
                             ["cpu"])
            self.assertIn("QOSMaxGRESPerUser", blocked.stderr)
            resumed = subprocess.run(["bash", str(script), str(root)],
                                     env=env, capture_output=True,
                                     text=True)
            self.assertEqual(resumed.returncode, 0, resumed.stderr)
            with (root / "jss_stage_jobs.tsv").open() as stream:
                jobs = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual([job["role"] for job in jobs],
                             ["cpu", "cuda", "paired", "extended"])

    def test_compute_launcher_refuses_login_execution(self):
        env = dict(os.environ, FASTEMBEDR_HPC_GPU_PAUSED="0")
        env.pop("SLURM_JOB_ID", None)
        run = subprocess.run(["bash", str(SUITE / "launch.sh")],
                             env=env, capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertIn("do not run containers on login", run.stderr)

    def test_gpu_pause_blocks_stage_before_submission(self):
        with tempfile.TemporaryDirectory() as directory:
            script, root, env = self.stage_fixture(directory)
            env.pop("FASTEMBEDR_HPC_GPU_PAUSED")
            run = subprocess.run(["bash", str(script), str(root)],
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 2)
            self.assertIn("GPU submissions remain paused", run.stderr)
            self.assertFalse((Path(directory) / "sbatch_args").exists())

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
                       FASTEMBEDR_HPC_GPU_PAUSED="0",
                       PATH=str(bin_dir) + os.pathsep +
                       os.pathsep.join(("/usr/bin", "/bin")))
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
