#!/usr/bin/env python3
"""Reject an incomplete or ambiguous file-backed campaign registry."""
import csv
from collections import Counter
from pathlib import Path


def main():
    path = Path(__file__).with_name("cases.csv")
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    ids = [row["id"] for row in rows]
    assert len(ids) == len(set(ids)) == 44
    assert Counter(row["analysis"] for row in rows) == {
        "matched": 4, "scaling": 24, "boundary": 2,
        "full_landmark": 4, "multi_gpu": 8, "recovery": 2}
    matched = {row["dataset"] for row in rows
               if row["analysis"] == "matched"}
    assert matched == {"mass41", "flow18", "imagenet",
                       "FlowRepository_FR-FCM-ZYRM_files"}
    scaling = {(row["dataset"], int(row["rows"]), row["method"])
               for row in rows if row["analysis"] == "scaling"}
    assert scaling == {(dataset, size, method)
                       for dataset in ("turing", "deep")
                       for size in (100000, 1000000, 10000000)
                       for method in ("pca", "knn", "umap", "tsne")}
    multi = {(row["method"], row["devices"])
             for row in rows if row["analysis"] == "multi_gpu"}
    assert multi == {(method, devices)
                     for method in ("pca", "knn", "umap", "tsne")
                     for devices in ("0", "0:1")}
    assert {row["route"] for row in rows
            if row["analysis"] == "full_landmark"} == {
                "full", "landmark"}
    print("File-backed registry: PASS (44 cases)")


if __name__ == "__main__":
    main()
