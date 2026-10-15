import tempfile
import unittest
import os
import subprocess
import csv
import shutil
from pathlib import Path
from unittest.mock import patch

from plan import DATASETS, cases, main
from audit import audit, classify, wall_time


class RealDataPlanTests(unittest.TestCase):
    def test_matched_routes_and_explicit_multi_gpu_limit(self):
        for dataset in DATASETS:
            entries = list(cases(dataset))
            self.assertEqual(len(entries), len({c["name"] for c in entries}))
            for mode in ("pca", "tsne", "umap"):
                for backend, cores in (("cpu", 1), ("cpu", 8),
                                       ("cuda", 1)):
                    pair = [c for c in entries if c["mode"] == mode and
                            c["backend"] == backend and
                            c["cores"] == cores and c["devices"] == "-"]
                    self.assertEqual({c["route"] for c in pair},
                                     {"classic", "file"})
            self.assertTrue(all(c["route"] == "file" for c in entries
                                if c["devices"] == "0,1"))

    def test_manifests_and_failure_classes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "campaign"
            main(root)
            for dataset in DATASETS:
                self.assertTrue((root / dataset / "cases.tsv").is_file())
                self.assertIn("Classic fit does not accept devices",
                    (root / dataset /
                     "unsupported_routes.tsv").read_text())
            time = root / "time.txt"
            time.write_text("Elapsed (wall clock) time (h:mm:ss or m:ss): "
                            "1:02.50\nMaximum resident set size "
                            "(kbytes): 1024\n")
            self.assertEqual(wall_time(time), (62.5, 1_048_576))
        self.assertEqual(classify(None, "OUT_OF_MEMORY"), "memory_limit")
        self.assertEqual(classify(None, "TIMEOUT"), "time_limit")
        self.assertEqual(classify("124", "COMPLETED"), "time_limit")

    def test_matched_pairs_include_quality_and_memory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "campaign"
            main(root)
            for route, seconds, rss, trust in (
                    ("classic", 20, 2_000_000, 0.90),
                    ("file", 10, 1_000_000, 0.85)):
                case = root / "flow18/results" / f"{route}_cpu1_pca"
                case.mkdir(parents=True)
                (case / "status.tsv").write_text(
                    "exit_code\n0\n")
                (case / "metrics.csv").write_text("status\nok\n")
                (case / "visual_manifest.csv").write_text(
                    "plotted_rows\n1000021\n")
                (case / "quality.csv").write_text(
                    "trustworthiness,knn_preservation_30\n"
                    f"{trust},0.4\n")
                (case / "time.txt").write_text(
                    "Elapsed (wall clock) time (h:mm:ss or m:ss): "
                    f"0:{seconds}\nMaximum resident set size "
                    f"(kbytes): {rss // 1024}\n")
            with patch("audit.sacct_states", return_value={}):
                audit(root, "flow18")
            with (root / "flow18/matched_pairs.csv").open() as handle:
                pairs = list(csv.DictReader(handle))
            self.assertEqual(len(pairs), 1)
            self.assertEqual(float(pairs[0]["speed_ratio"]), 2)
            self.assertEqual(float(pairs[0]["file_trustworthiness"]),
                             0.85)
            self.assertGreater(float(pairs[0]["rss_ratio"]), 1)
            if shutil.which("Rscript"):
                plot = subprocess.run(["Rscript", str(Path(__file__).parent /
                    "plot_comparison.R"), str(root), "flow18"],
                    text=True, capture_output=True)
                self.assertEqual(plot.returncode, 0, plot.stderr)
                self.assertTrue((root / "flow18/comparison_time.png").is_file())
                self.assertTrue((root / "flow18/comparison_rss.png").is_file())

    def test_submit_keeps_dataset_and_gpu_lanes_independent(self):
        suite = Path(__file__).parent
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            for relative in (
                "singularity/fastembedr_cuda.sif",
                "benchmark_scripts/fastembedr_jss_review_validation/"
                "common/common.R",
                "benchmark_scripts/massive-data/run_scaling.R",
                "benchmark_scripts/massive-data/deep1b/gpu_memory.py",
            ):
                path = base / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture\n")
            bin_dir = base / "bin"
            bin_dir.mkdir()
            sbatch = bin_dir / "sbatch"
            sbatch.write_text("#!/bin/sh\necho 12345\n")
            sbatch.chmod(0o755)
            stat = bin_dir / "stat"
            stat.write_text("#!/bin/sh\necho 1:1:1:1:1\n")
            stat.chmod(0o755)
            sacct = bin_dir / "sacct"
            sacct.write_text("#!/bin/sh\necho '12345|COMPLETED|0:0'\n")
            sacct.chmod(0o755)
            env = os.environ.copy()
            env["REAL_BASE"] = str(base)
            env["PATH"] = str(bin_dir) + ":" + env["PATH"]
            run = subprocess.run(["bash", str(suite / "submit.sh")],
                                 env=env, text=True, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            roots = list((base / "fastEmbedR-results/massive-data/"
                          "real-data").iterdir())
            self.assertEqual(len(roots), 1)
            root = roots[0]
            jobs = (root / "jobs.tsv").read_text().splitlines()
            self.assertEqual(len(jobs), 28)
            for dataset in DATASETS:
                for lane, count in (("classic_cpu1", 3),
                                    ("file_cpu8", 4),
                                    ("classic_cuda1", 3),
                                    ("file_cuda2", 4)):
                    group = (root / dataset /
                             f"cases_{lane}.tsv").read_text().splitlines()
                    self.assertEqual(len(group) - 1, count)
            audit = subprocess.run(
                ["python3", str(suite / "audit.py"), str(root), "flow18"],
                env=env, text=True, capture_output=True)
            self.assertEqual(audit.returncode, 0, audit.stderr)
            self.assertTrue((root / "flow18/all_cases.csv").is_file())


if __name__ == "__main__":
    unittest.main()
