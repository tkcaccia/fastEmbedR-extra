#!/usr/bin/env python3
"""Descriptive neighbor-vs-random layout diagnostic for Deep1B 100M."""

import csv
import hashlib
import json
import math
import mmap
import statistics
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path


ROWS = 100_000_000
K = 30
QUERIES = 4_096
SEED = 4
MASK = (1 << 64) - 1
LAYOUTS = ("pca_cpu20", "pca_metal", "tsne_cpu20", "umap_cpu1",
           "umap_cpu20", "umap_metal")


def require(ok, message):
    if not ok:
        raise ValueError(message)


def mix64(value):
    value = (value + 0x9E3779B97F4A7C15) & MASK
    value = ((value ^ (value >> 30)) *
             0xBF58476D1CE4E5B9) & MASK
    value = ((value ^ (value >> 27)) *
             0x94D049BB133111EB) & MASK
    return value ^ (value >> 31)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(8 * 1024 * 1024):
            result.update(block)
    return result.hexdigest()


def expected_hashes(run):
    with (run / "postprocess-audit-v1/files.sha256.csv").open(
            newline="") as stream:
        records = list(csv.DictReader(stream))
    return {record["path"]: record["sha256"] for record in records}


def verified(path, expected, size):
    require(path.is_file() and path.stat().st_size == size,
            f"Layout diagnostic input size changed: {path}")
    require(expected.get(str(path)) == digest(path),
            f"Layout diagnostic input hash changed: {path}")


def query_pairs(knn_path):
    result = []
    with knn_path.open("rb") as stream:
        graph = mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            for i in range(QUERIES):
                query = (1_234_567 + i * 24_413) % ROWS
                neighbors = struct.unpack_from(
                    f"<{K}I", graph, query * K * 4)
                require(len(set(neighbors)) == K and
                        all(1 <= x <= ROWS and x != query + 1
                            for x in neighbors),
                        f"Invalid sampled graph row: {query}")
                samples = []
                for j, neighbor in enumerate(neighbors):
                    candidate = mix64(SEED + query * K + j) % ROWS
                    while (candidate == query or
                           candidate + 1 in neighbors):
                        candidate = (candidate + 1) % ROWS
                    samples.append((neighbor - 1, candidate))
                result.append((query, samples))
        finally:
            graph.close()
    return result


def coordinate(layout, row):
    x, y = struct.unpack_from("<ff", layout, row * 8)
    require(math.isfinite(x) and math.isfinite(y),
            f"Nonfinite sampled layout row: {row}")
    return x, y


def squared(first, second):
    return (first[0] - second[0]) ** 2 + (
        first[1] - second[1]) ** 2


def score_layout(path, pairs):
    per_query = []
    with path.open("rb") as stream:
        layout = mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            for query, candidates in pairs:
                origin = coordinate(layout, query)
                wins = 0.0
                for neighbor, negative in candidates:
                    positive = squared(origin,
                                       coordinate(layout, neighbor))
                    control = squared(origin,
                                      coordinate(layout, negative))
                    require(math.isfinite(positive) and
                            math.isfinite(control),
                            "Nonfinite sampled layout distance")
                    wins += (1.0 if positive < control else
                             0.5 if positive == control else 0.0)
                per_query.append(wins / K)
        finally:
            layout.close()
    ordered = sorted(per_query)
    return {
        "query_rows": QUERIES, "neighbors_per_query": K,
        "paired_comparisons": QUERIES * K,
        "neighbor_vs_random_win_rate": statistics.mean(per_query),
        "query_rate_sd": statistics.pstdev(per_query),
        "query_rate_p05": ordered[int(0.05 * (QUERIES - 1))],
        "query_rate_p50": statistics.median(per_query),
        "query_rate_p95": ordered[int(0.95 * (QUERIES - 1))],
    }


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: script.py DEEP1B_RUN_ROOT")
    run = Path(sys.argv[1]).resolve()
    require(str(run).startswith(
            "/Users/silvanopiazza/Documents/Stefano/"),
            "Layout diagnostic must stay under Stefano")
    require((run / "postprocess/postprocess.exit").read_text().strip() ==
            "0", "Independent structural audit has not passed")
    hashes = expected_hashes(run)
    knn = run / "cases/knn_cpu20/knn.indices.u32"
    verified(knn, hashes, ROWS * K * 4)
    paths = {stage: run / "cases" / stage /
             ("scores.f32" if stage.startswith("pca_") else
              "layout.f32") for stage in LAYOUTS}
    for path in paths.values():
        verified(path, hashes, ROWS * 2 * 4)
    pairs = query_pairs(knn)
    rows = []
    for stage, path in paths.items():
        rows.append({"stage": stage, **score_layout(path, pairs)})
    out = run / "layout-quality-v1"
    out.mkdir(exist_ok=False)
    with (out / "neighbor_vs_random.csv").open(
            "w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    (out / "method.json").write_text(json.dumps({
        "status": "descriptive_diagnostic", "rows": ROWS, "k": K,
        "query_rows": QUERIES, "seed": SEED,
        "query_formula": "(1234567 + i * 24413) % 100000000",
        "negative_formula": "splitmix64(4 + query * 30 + j) % 100000000",
        "interpretation": "Fraction of sampled full-KNN edges closer in 2D "
            "than matched deterministic random vertices; no global quality "
            "or speed qualification is implied.",
        "completed_utc": datetime.now(timezone.utc).isoformat(),
    }, indent=2, sort_keys=True) + "\n")
    print("Saved six descriptive 100M layout diagnostics")


if __name__ == "__main__":
    main()
