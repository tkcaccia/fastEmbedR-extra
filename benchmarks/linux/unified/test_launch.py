"""Login-side submission must not execute the benchmark itself."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SUITE = Path(__file__).resolve().parent


class UnifiedLaunchTest(unittest.TestCase):
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
