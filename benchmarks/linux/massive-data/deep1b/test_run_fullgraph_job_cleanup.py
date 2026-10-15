"""Failed full-graph jobs must retain their output and scratch evidence."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("run_fullgraph_job.sh")


class FullGraphCleanupTest(unittest.TestCase):
    def test_source_lock_failure_preserves_payloads(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            input_path = (base / "Data/BigANN/deep/1000000000" /
                          "base.1000000000.fbin")
            input_path.parent.mkdir(parents=True)
            input_path.write_bytes(b"input")
            root = base / "campaign"
            work = root / "work"
            result = root / "results/cpu_pca_1000_fullgraph"
            work.mkdir(parents=True)
            result.mkdir(parents=True)
            (work / "knn.indices.u32").write_bytes(b"graph")
            (result / "output.f32").write_bytes(b"scores")
            (root / "source.sha256").write_text(
                "0" * 64 + "  " + str(input_path) + "\n")
            env = dict(os.environ, DEEP1B_BASE=str(base),
                       DEEP1B_FULLGRAPH_ROOT=str(root),
                       BIGANN_DATASET="deep", DEEP1B_BACKEND="cpu",
                       DEEP1B_FULLGRAPH_ROWS="1000")
            run = subprocess.run(["bash", str(SCRIPT)], env=env,
                                 capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual((work / "knn.indices.u32").read_bytes(),
                             b"graph")
            self.assertEqual((result / "output.f32").read_bytes(),
                             b"scores")
            audit = json.loads((root / "audit.json").read_text())
            self.assertEqual(audit["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
