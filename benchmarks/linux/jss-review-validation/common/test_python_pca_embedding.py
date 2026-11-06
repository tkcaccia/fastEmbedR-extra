#!/usr/bin/env python3

import csv
import gzip
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np


def main():
    worker = Path(__file__).with_name("run_python_comparator.py")
    with tempfile.TemporaryDirectory(prefix="jss-pca-") as directory:
        root = Path(directory)
        inputs = root / "input"
        output = root / "output"
        inputs.mkdir()
        output.mkdir()
        values = np.random.default_rng(4).normal(size=(64, 8))
        values.astype("<f4").tofile(inputs / "data_float32.bin")
        with (inputs / "manifest.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=(
                "dataset", "n", "p", "quality_n"
            ))
            writer.writeheader()
            writer.writerow({"dataset": "synthetic", "n": 64,
                             "p": 8, "quality_n": 16})
        with (inputs / "rows_labels.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=(
                "source_row", "label", "quality_sample"
            ))
            writer.writeheader()
            writer.writerows({"source_row": index, "label": "x",
                              "quality_sample": index <= 16}
                             for index in range(1, 65))
        subprocess.run((
            sys.executable, str(worker), f"--input-dir={inputs}",
            f"--output-dir={output}", "--dataset=synthetic",
            "--method=sklearn_pca", "--backend=cpu", "--threads=1",
            "--timing-reps=2", "--defer-quality",
        ), check=True, timeout=120)
        with gzip.open(output / "embedding.csv.gz", "rt",
                       newline="") as handle:
            rows = list(csv.DictReader(handle))
        assert len(rows) == 64
        assert [int(row["source_row"]) for row in rows] == list(range(1, 65))
        assert all("dimension_2" in row for row in rows)
        with (output / "status.csv").open(newline="") as handle:
            assert next(csv.DictReader(handle))["status"] == "success"
        with (output / "result.csv").open(newline="") as handle:
            result = next(csv.DictReader(handle))
        assert int(result["n"]) == 64
        assert int(result["pca_rank"]) == 7
    print("Python PCA embedding contract: PASS")


if __name__ == "__main__":
    main()
