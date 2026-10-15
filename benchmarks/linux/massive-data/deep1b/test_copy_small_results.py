#!/usr/bin/env python3
"""Ensure the small-evidence transfer never includes large payload types."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


class CopySmallResultsTest(unittest.TestCase):
    def test_excludes_input_output_and_checkpoints(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            remote = root / "remote"
            case = remote / "deep1b" / "campaign" / "results" / "case"
            case.mkdir(parents=True)
            for name in ("metrics.csv", "quality.csv", "image.stat",
                         "visual_manifest.csv", "plot_sample.csv.gz",
                         "all_cases.csv", "matched_pairs.csv",
                         "hnsw_shards.csv.gz", "knn_audit_rows.csv.gz",
                         "knn_device_audit.csv",
                         "plot_density.png", "source_label_legend.csv",
                         "output.f32", "input.fbin", "embedding.csv",
                         "checkpoint.rds"):
                (case / name).write_bytes(b"content")
            local = root / "local"
            script = Path(__file__).with_name("copy_small_results.sh")
            env = dict(os.environ, HPC_HOST="local",
                       HPC_RESULT_ROOT=str(remote),
                       LOCAL_RESULT_ROOT=str(local))
            subprocess.run(["bash", str(script)], env=env,
                           check=True, capture_output=True, text=True)
            target = local / "deep1b" / "campaign" / "results" / "case"
            self.assertEqual({path.name for path in target.iterdir()},
                             {"metrics.csv", "quality.csv", "image.stat",
                              "visual_manifest.csv",
                              "plot_sample.csv.gz", "all_cases.csv",
                              "matched_pairs.csv", "hnsw_shards.csv.gz",
                              "knn_audit_rows.csv.gz", "plot_density.png",
                              "knn_device_audit.csv",
                              "source_label_legend.csv"})


if __name__ == "__main__":
    unittest.main()
