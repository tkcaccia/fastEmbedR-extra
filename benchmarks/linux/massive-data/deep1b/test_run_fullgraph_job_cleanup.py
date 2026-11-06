"""Failed full-graph jobs must retain their output and scratch evidence."""

import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("run_fullgraph_job.sh")


class FullGraphCleanupTest(unittest.TestCase):
    def test_scored_outputs_are_pruned_only_after_figures_exist(self):
        script = SCRIPT.read_text()
        functions = []
        for name in ("prune_outputs", "prune_work"):
            match = re.search(rf"(?ms)^{name}\(\) \{{.*?^\}}", script)
            self.assertIsNotNone(match)
            functions.append(match.group())
        harness = (
            'set -euo pipefail\nroot=$1\nbackend=cpu\nrows=1000\n'
            'label=fullgraph\n'
            'case_name() { printf "%s_%s_%s_%s" '
            '"$backend" "$1" "$rows" "$label"; }\n'
            + "\n".join(functions) + '\nprune_outputs\nprune_work\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = os.environ.copy()
            if shutil.which("gstat"):
                bin_dir = root / "bin"
                bin_dir.mkdir()
                (bin_dir / "stat").symlink_to(shutil.which("gstat"))
                env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
            work = root / "work"
            work.mkdir()
            (work / "leiden_labels.u32").write_bytes(b"labels")
            (work / "knn.indices.u32").write_bytes(b"graph")
            expected = {}
            for method in ("pca", "tsne", "umap"):
                name = f"cpu_{method}_1000_fullgraph"
                result = root / "results" / name
                result.mkdir(parents=True)
                data = method.encode()
                (result / "output.f32").write_bytes(data)
                (result / "coverage.csv").write_text(
                    "rows_scanned,all_values_valid\n1000,TRUE\n")
                (result / "quality.csv").write_text("score\n1\n")
                figure = root / "figures" / f"{name}.png"
                figure.parent.mkdir(exist_ok=True)
                figure.write_bytes(b"png")
                expected[f"results/{name}/output.f32"] = (
                    str(len(data)), hashlib.sha256(data).hexdigest())
            missing = root / "results/cpu_umap_1000_fullgraph/quality.csv"
            missing.unlink()
            failed = subprocess.run(["bash", "-c", harness, "bash",
                                     str(root)], capture_output=True,
                                    env=env)
            self.assertNotEqual(failed.returncode, 0)
            self.assertTrue((work / "knn.indices.u32").exists())
            self.assertTrue(all((root / path).exists()
                                for path in expected))
            missing.write_text("score\n1\n")
            coverage = (root / "results/cpu_umap_1000_fullgraph/"
                        "coverage.csv")
            coverage.unlink()
            failed = subprocess.run(["bash", "-c", harness, "bash",
                                     str(root)], capture_output=True,
                                    env=env)
            self.assertNotEqual(failed.returncode, 0)
            self.assertTrue(all((root / path).exists()
                                for path in expected))
            coverage.write_text("rows_scanned,all_values_valid\n"
                                "1000,TRUE\n")
            passed = subprocess.run(["bash", "-c", harness, "bash",
                                     str(root)], capture_output=True,
                                    env=env)
            self.assertEqual(passed.returncode, 0, passed.stderr)
            self.assertFalse(any((root / path).exists()
                                 for path in expected))
            self.assertFalse(any(work.iterdir()))
            with (root / "pruned_outputs.tsv").open(newline="") as stream:
                rows = list(csv.DictReader(stream, delimiter="\t"))
            self.assertEqual({row["path"]: (row["bytes"], row["sha256"])
                              for row in rows}, expected)

    def test_classic_audit_expects_only_classic_runner_outputs(self):
        script = SCRIPT.read_text()
        classic = re.search(
            r'if \[\[ "\$mode" == classic \]\]; then(.*?)\nelif',
            script, re.DOTALL).group(1)
        expected = re.search(r'methods=\(([^)]+)\)', classic)
        self.assertIsNotNone(expected)
        runner = SCRIPT.with_name("run_classic_1m.R").read_text()
        produced = re.search(r'methods <- c\(([^)]+)\)', runner)
        self.assertIsNotNone(produced)
        self.assertEqual(set(expected.group(1).split()),
                         set(re.findall(r'"([^"]+)"', produced.group(1))))

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
