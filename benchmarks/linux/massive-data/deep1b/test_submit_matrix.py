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
    def test_plan_covers_rows_and_hardware_without_gpu_gating_cpu(self):
        result = subprocess.run(["bash", str(SCRIPT), "--plan"],
                                check=True, capture_output=True,
                                text=True)
        rows = list(csv.DictReader(io.StringIO(result.stdout),
                                   delimiter="\t"))
        self.assertEqual(len(rows), 26)
        self.assertEqual({row["mode"] for row in rows},
                         {"classic", "full"})
        expected_sizes = {1_000_000, 10_000_000,
                          50_000_000, 100_000_000}
        for lane in ("cpu4", "cpu8", "cpu16",
                     "cuda1", "cuda2", "cuda4"):
            cases = [row for row in rows if row["lane"] == lane and
                     row["mode"] == "full"]
            self.assertEqual({int(row["rows"]) for row in cases},
                             expected_sizes)
            for case in cases:
                if int(case["rows"]) <= 10_000_000:
                    self.assertEqual(case["depends_on"], "-")
                dependencies = case["depends_on"].split(",")
                if lane.startswith("cpu"):
                    self.assertTrue(all(item == "-" or
                                        item.startswith("cpu")
                                        for item in dependencies))
                else:
                    self.assertTrue(all(item == "-" or
                                        item.startswith(lane + "_") or
                                        (lane == "cuda2" and
                                         item == "cuda1_100000000") or
                                        (lane == "cuda4" and
                                         item == "cuda2_100000000")
                                        for item in dependencies))
        largest_cpu = next(row for row in rows
                           if row["lane"] == "cpu16" and
                           row["rows"] == "100000000")
        self.assertEqual(largest_cpu["depends_on"],
                         "cpu16_50000000,cpu4_100000000")
        two_gpu = next(row for row in rows
                       if row["lane"] == "cuda2" and
                       row["rows"] == "100000000")
        self.assertEqual(two_gpu["depends_on"],
                         "cuda2_50000000,cuda1_100000000")
        largest_gpu = next(row for row in rows
                           if row["lane"] == "cuda4" and
                           row["rows"] == "100000000")
        self.assertEqual(largest_gpu["depends_on"],
                         "cuda4_50000000,cuda2_100000000")
        classic = [row for row in rows if row["mode"] == "classic"]
        self.assertEqual(len(classic), 2)
        self.assertTrue(all(row["depends_on"] == "-"
                            for row in classic))
        boundary = [row for row in rows if row["mode"] == "full"
                    and row["rows"] == "100000000"
                    and row["lane"] == "cpu4"]
        self.assertEqual(len(boundary), 1)
        self.assertEqual(boundary[0]["job_memory"], "32G")
        self.assertTrue(all(row["job_memory"] == "64G"
                            for row in rows if row not in boundary))

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
            for name in ("run_fullgraph_job.sh", "run_full_graph.R"):
                (suite / name).write_text("# fixture\n")
            (suite / "submit_fullgraph5m.sh").write_text(
                "#!/bin/bash\n"
                "if [[ \"${TEST_BLOCK_CUDA4:-}\" == 1 && "
                "\"$DEEP1B_GPU_DEVICES\" == 0,1,2,3 ]]; then\n"
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
                       DEEP1B_QUOTA_FREE_BYTES="9999999999999",
                       PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])
            run = subprocess.run(["bash", str(suite / SCRIPT.name)],
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            ledger = next((base / "fastEmbedR-results/massive-data/"
                           "deep1b_matrix").glob("*/jobs.tsv"))
            jobs = csv_rows(ledger)
            self.assertEqual(len(jobs), 26)
            lookup = {(row["mode"], row["rows"], row["lane"]): row
                      for row in jobs}
            self.assertEqual(lookup[("full", "1000000", "cpu4")]
                             ["dependency"], "-")
            self.assertEqual(lookup[("full", "10000000", "cpu4")]
                             ["dependency"], "-")
            self.assertEqual(lookup[("full", "50000000", "cpu4")]
                             ["dependency"],
                             lookup[("full", "10000000", "cpu4")]["job"])
            self.assertEqual(lookup[("full", "100000000", "cpu4")]
                             ["job_memory"], "32G")
            self.assertTrue(all(row["job_memory"] == "64G" for row in jobs
                                if row is not lookup[("full", "100000000",
                                                  "cpu4")]))
            with (base / "dependencies").open(newline="") as stream:
                dependencies = list(csv.reader(stream, delimiter="\t"))
            self.assertTrue(all(row[5] == "afterany"
                                for row in dependencies))
            self.assertIn(["full", "100000000", "4",
                           lookup[("full", "50000000", "cpu4")]["job"],
                           "32G", "afterany"], dependencies)
            for row in jobs:
                if row["lane"].startswith("cpu"):
                    self.assertNotIn(
                        lookup[("full", "10000000", "cuda1")]["job"],
                        row["dependency"].split(":"))
            two_gpu = lookup[("full", "100000000", "cuda2")]
            self.assertEqual(two_gpu["dependency"], ":".join((
                lookup[("full", "50000000", "cuda2")]["job"],
                lookup[("full", "100000000", "cuda1")]["job"])))
            lines = ledger.read_text().splitlines()
            ledger.write_text("\n".join(lines[:-4]) + "\n")
            blocked_env = dict(env, TEST_BLOCK_CUDA4="1",
                               TEST_GPU_JOBS="1")
            resume = subprocess.run(
                ["bash", str(suite / SCRIPT.name), "--resume",
                 str(ledger)], env=blocked_env, capture_output=True,
                text=True)
            self.assertEqual(resume.returncode, 0, resume.stderr)
            self.assertEqual(len(csv_rows(ledger)), 22)
            self.assertIn("2001:2002", (base / "sbatch_args").read_text())
            self.assertIn("controller_job\t9999",
                          (ledger.parent / "resume.tsv").read_text())
            resume = subprocess.run(
                ["bash", str(suite / SCRIPT.name), "--resume",
                 str(ledger)], env=env, capture_output=True, text=True)
            self.assertEqual(resume.returncode, 0, resume.stderr)
            self.assertEqual(len(csv_rows(ledger)), 26)


if __name__ == "__main__":
    unittest.main()
