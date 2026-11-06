"""The Deep1B matrix must expose its hardware and dependency contract."""

import csv
import io
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("submit_matrix.sh")


def csv_rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


class MatrixPlanTest(unittest.TestCase):
    def test_active_cpu_jobs_do_not_block_cuda_lane(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            suite = base / "benchmark_scripts/massive-data/deep1b"
            suite.mkdir(parents=True)
            (suite / "submit_fullgraph5m.sh").write_text("# fixture\n")
            image = base / "image.sif"
            image.write_bytes(b"fixture")
            bin_dir = base / "bin"
            bin_dir.mkdir()
            squeue = bin_dir / "squeue"
            squeue.write_text("#!/bin/sh\necho feR_fg_deep_cpu\n")
            squeue.chmod(0o755)
            env = dict(os.environ, DEEP1B_BASE=str(base),
                       DEEP1B_IMAGE=str(image),
                       FASTEMBEDR_HPC_GPU_PAUSED="0",
                       PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            cpu = subprocess.run(["bash", str(SCRIPT)],
                                 env=dict(env, DEEP1B_LANE_GROUP="cpu"),
                                 capture_output=True, text=True)
            self.assertEqual(cpu.returncode, 2)
            self.assertIn("earlier cpu", cpu.stderr)
            cuda = subprocess.run(["bash", str(SCRIPT)],
                                  env=dict(env, DEEP1B_LANE_GROUP="cuda"),
                                  capture_output=True, text=True)
            self.assertNotIn("earlier cuda", cuda.stderr)

    def test_lane_groups_have_independent_plans(self):
        for group, lanes in (("cpu", {"cpu4", "cpu8", "cpu16"}),
                             ("cuda", {"cuda1", "cuda2"})):
            env = dict(os.environ, DEEP1B_LANE_GROUP=group)
            result = subprocess.run(
                ["bash", str(SCRIPT), "--plan"], env=env,
                check=True, capture_output=True, text=True)
            rows = list(csv.DictReader(io.StringIO(result.stdout),
                                       delimiter="\t"))
            expected = {"cpu": 7, "cuda": 5}[group]
            self.assertEqual(len(rows), expected)
            self.assertEqual({row["lane"] for row in rows}, lanes)
            self.assertTrue(all(row["depends_on"] == "-"
                                for row in rows))
            if group == "cpu":
                self.assertTrue(all(row["job_time"] == "3-00:00:00"
                                    for row in rows))
            if group == "cuda":
                short = [row for row in rows
                         if row["allocation"] == "short_cuda1"]
                self.assertEqual(short, [])

    def test_plan_covers_rows_and_hardware_without_gpu_gating_cpu(self):
        result = subprocess.run(["bash", str(SCRIPT), "--plan"],
                                check=True, capture_output=True,
                                text=True)
        rows = list(csv.DictReader(io.StringIO(result.stdout),
                                   delimiter="\t"))
        self.assertEqual(len(rows), 12)
        self.assertEqual({row["mode"] for row in rows},
                         {"classic", "full"})
        expected_sizes = {1_000_000, 10_000_000}
        for lane in ("cpu4", "cpu8", "cpu16",
                     "cuda1", "cuda2"):
            cases = [row for row in rows if row["lane"] == lane and
                     row["mode"] == "full"]
            self.assertEqual({int(row["rows"]) for row in cases},
                             expected_sizes)
            for case in cases:
                self.assertEqual(case["depends_on"], "-")
                if lane == "cuda2" and \
                        case["rows"] == "1000000":
                    self.assertEqual(case["job_time"], "04:00:00")
                if case["rows"] == "10000000" and lane.startswith("cuda"):
                    self.assertEqual(case["job_time"], "08:00:00")
        classic = [row for row in rows if row["mode"] == "classic"]
        self.assertEqual(len(classic), 2)
        self.assertTrue(all(row["depends_on"] == "-"
                            for row in classic))
        self.assertTrue(all(row["job_time"] == "3-00:00:00"
                            for row in rows if row["lane"].startswith("cpu")))
        self.assertTrue(all(row["job_memory"] == "64G" for row in rows))

    def test_submitted_dependencies_match_plan(self):
        supported = subprocess.run(
            ["bash", "-c", "declare -A matrix"],
            capture_output=True)
        if supported.returncode:
            self.skipTest("Submission simulation requires Bash 4 or newer")
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            suite = base / "benchmark_scripts/massive-data/deep1b"
            suite.mkdir(parents=True)
            shutil.copy2(SCRIPT, suite / SCRIPT.name)
            (suite / "preflight_fullgraph.py").write_text(
                "def storage_plan(rows, mode, available_bytes, "
                "rebuild_knn=False):\n"
                "    return {'worst_case_bytes': rows * 100}\n")
            (suite / "validate_input.py").write_text("print('ok')\n")
            for name in ("run_fullgraph_job.sh", "run_full_graph.R",
                         "audit_output.R", "run_short_cuda_bundle.sh"):
                (suite / name).write_text("# fixture\n")
            (suite / "submit_short_cuda_bundle.sh").write_text(
                "#!/bin/bash\n"
                "base=$DEEP1B_BASE\n"
                "next=$(cat \"$base/counter\")\n"
                "next=$((next+1))\n"
                "printf '%s' \"$next\" > \"$base/counter\"\n"
                "printf 'deep\\tcuda\\tclassic\\t1000000\\t%s\\t%s\\n' "
                "\"$next\" \"$base/short-classic\"\n"
                "printf 'deep\\tcuda\\tfull\\t1000000\\t%s\\t%s\\n' "
                "\"$next\" \"$base/short-full\"\n")
            (suite / "submit_fullgraph5m.sh").write_text(
                "#!/bin/bash\n"
                "if [[ \"${TEST_BLOCK_CUDA2:-}\" == 1 && "
                "\"$DEEP1B_GPU_DEVICES\" == 0,1 ]]; then\n"
                "  echo QOSMaxGRESPerUser >&2; exit 1\n"
                "fi\n"
                "base=$DEEP1B_BASE\n"
                "next=$(cat \"$base/counter\")\n"
                "next=$((next+1))\n"
                "printf '%s' \"$next\" > \"$base/counter\"\n"
                "printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "
                "deep \"$DEEP1B_BACKEND_FILTER\" "
                "\"$DEEP1B_FIT_MODE\" \"$DEEP1B_FULLGRAPH_ROWS\" "
                "\"$next\" \"$base/campaign-$next\"\n"
                "printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "
                "\"$DEEP1B_FIT_MODE\" \"$DEEP1B_FULLGRAPH_ROWS\" "
                "\"$DEEP1B_CPU_CORES\" \"$DEEP1B_AFTER_JOB\" "
                "\"$DEEP1B_JOB_MEMORY\" \"$DEEP1B_DEPENDENCY_TYPE\" "
                ">> \"$base/dependencies\"\n")
            (base / "counter").write_text("1000")
            image = base / "image.sif"
            image.write_bytes(b"fixture")
            bin_dir = base / "bin"
            bin_dir.mkdir()
            for name, contents in (
                ("squeue", "#!/bin/sh\n"
                 "if [ \"${TEST_GPU_JOBS:-}\" = 1 ]; then\n"
                 "  printf '2001\\n2002\\n'\nfi\n"),
                ("df", "#!/bin/sh\nprintf 'Avail\\n9999999999999\\n'\n"),
                ("purequota", "#!/bin/sh\n"
                 "echo '/scratch 999999GB 0GB 0%'\n"),
                ("sbatch", "#!/bin/sh\n"
                 "printf '%s\\n' \"$@\" > \"$DEEP1B_BASE/sbatch_args\"\n"
                 "echo 9999\n")):
                command = bin_dir / name
                command.write_text(contents)
                command.chmod(0o755)
            env = dict(os.environ, DEEP1B_BASE=str(base),
                       DEEP1B_IMAGE=str(image),
                       FASTEMBEDR_HPC_GPU_PAUSED="0",
                       DEEP1B_BUNDLE_SHORT_CUDA="1",
                       DEEP1B_QUOTA_FREE_BYTES="9999999999999",
                       PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            run = subprocess.run(["bash", str(suite / SCRIPT.name)],
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            ledger = next((base / "fastEmbedR-results/massive-data/"
                           "deep1b_matrix").glob("*/jobs.tsv"))
            jobs = csv_rows(ledger)
            self.assertEqual(len(jobs), 12)
            lookup = {(row["mode"], row["rows"], row["lane"]): row
                      for row in jobs}
            self.assertEqual(lookup[("full", "1000000", "cpu4")]
                             ["dependency"], "-")
            self.assertEqual(lookup[("classic", "1000000", "cuda1")]
                             ["job"],
                             lookup[("full", "1000000", "cuda1")]
                             ["job"])
            self.assertEqual(lookup[("full", "10000000", "cpu4")]
                             ["dependency"], "-")
            self.assertEqual({int(row["rows"]) for row in jobs},
                             {1_000_000, 10_000_000})
            self.assertNotIn("cuda3", {row["lane"] for row in jobs})
            self.assertTrue(all(row["job_memory"] == "64G"
                                for row in jobs))
            with (base / "dependencies").open(newline="") as stream:
                dependencies = list(csv.reader(stream, delimiter="\t"))
            self.assertTrue(all(row[5] == "afterok"
                                for row in dependencies))
            for row in jobs:
                self.assertEqual(row["dependency"], "-")
            lines = ledger.read_text().splitlines()
            ledger.write_text("\n".join(lines[:-1]) + "\n")
            blocked_env = dict(env, TEST_BLOCK_CUDA2="1",
                               TEST_GPU_JOBS="1")
            resume = subprocess.run(
                ["bash", str(suite / SCRIPT.name), "--resume",
                 str(ledger)], env=blocked_env, capture_output=True,
                text=True)
            self.assertEqual(resume.returncode, 3, resume.stderr)
            self.assertEqual(len(csv_rows(ledger)), 11)
            self.assertIn("QOSMaxGRESPerUser", resume.stderr)
            self.assertFalse((ledger.parent / "resume.tsv").exists())
            resume = subprocess.run(
                ["bash", str(suite / SCRIPT.name), "--resume",
                 str(ledger)], env=env, capture_output=True, text=True)
            self.assertEqual(resume.returncode, 0, resume.stderr)
            self.assertEqual(len(csv_rows(ledger)), 12)


if __name__ == "__main__":
    unittest.main()
