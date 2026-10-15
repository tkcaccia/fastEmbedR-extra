"""Method summaries must preserve partial and unsupported outcomes."""

import csv
import json
import tempfile
import unittest
from pathlib import Path

from summarize_matrix import summarize_case


def write_csv(path, row, delimiter=","):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, row.keys(), delimiter=delimiter)
        writer.writeheader()
        writer.writerow(row)


class SummaryTest(unittest.TestCase):
    def test_single_gpu_clustering_is_explicitly_unsupported(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            job = dict(mode="full", rows="3", lane="cuda1", job="12")
            (root / "audit.json").write_text(
                json.dumps({"status": "PASS"}))
            write_csv(root / "knn.csv", dict(observed_recall="0.99",
                      minimum_row_recall="0.9"))
            write_csv(root / "unsupported_methods.tsv", dict(
                method="leiden", reason="needs 2-4 GPUs"), "\t")
            for method in ("pca", "tsne", "umap"):
                name = f"cuda_{method}_3_fullgraph"
                case = root / "results" / name
                write_csv(case / "metrics.csv", dict(status="ok"))
                (case / "output.f32").write_bytes(bytes(24))
                figure = root / "figures" / (name + ".png")
                figure.parent.mkdir(exist_ok=True)
                figure.write_bytes(b"png")
            rows = summarize_case(job, root)
            by_method = {row["method"]: row for row in rows}
            self.assertEqual(by_method["knn"]["knn_recall_mean"],
                             "0.99")
            self.assertEqual(by_method["umap"]["status"], "ok")
            self.assertEqual(by_method["leiden"]["status"],
                             "unsupported")
            self.assertEqual(by_method["louvain"]["status"],
                             "missing")


if __name__ == "__main__":
    unittest.main()
