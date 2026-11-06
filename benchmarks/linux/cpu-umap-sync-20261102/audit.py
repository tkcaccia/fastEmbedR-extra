#!/usr/bin/env python3
"""Audit the two ordered MNIST70k CPU UMAP pilot passes."""

import csv
import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent / "evidence"
EXPECTED = "4c432f79ed2bf7a503e891a087eeda83a7f0d067ac39647e4e301306ed4f953a"
ORDERS = {"v1": [1, 2, 4, 8], "v2": [8, 4, 2, 1]}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def audit_pass(version, expected_order):
    folder = ROOT / f"chiamaka-mnist70k-{version}"
    for line in (folder / "SHA256SUMS").read_text().splitlines():
        recorded, name = line.split("  ", 1)
        assert sha256(folder / name) == recorded, name
    assert (folder / f"cpu-umap-sync-mnist70k-{version}.exit").read_text().strip() == "0"
    rows = list(csv.DictReader((folder / "summary.csv").open()))
    assert [int(row["workers_requested"]) for row in rows] == expected_order
    assert len(rows) == 4
    for row in rows:
        assert row["dataset"] == "MNIST70k"
        assert row["backend"] == "cpu"
        assert row["optimizer"] == "synchronized_cpu_fixed_point"
        assert row["workers_requested"] == row["workers_effective"]
        assert int(row["graph_edges"]) == 1588812
        assert int(row["epochs"]) == 200
        assert row["output_sha256"] == EXPECTED
        assert float(row["fit_elapsed_sec"]) > 0
    layout_name = "umap_sync_cpu1.f32" if version == "v1" else "umap_sync_cpu8.f32"
    layout = folder / layout_name
    assert layout.stat().st_size == 70000 * 2 * 4
    assert sha256(layout) == EXPECTED
    return {int(row["workers_requested"]): float(row["fit_elapsed_sec"])
            for row in rows}


if __name__ == "__main__":
    forward = audit_pass("v1", ORDERS["v1"])
    reverse = audit_pass("v2", ORDERS["v2"])
    mean = {worker: (forward[worker] + reverse[worker]) / 2
            for worker in ORDERS["v1"]}
    print("PASS: two ordered passes, eight fits, identical 70k-row layouts")
    print("mean fit seconds:", mean)
    print("one-to-eight worker ratio:", round(mean[1] / mean[8], 3))
