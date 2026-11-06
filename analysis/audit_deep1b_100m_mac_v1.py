#!/usr/bin/env python3
"""Independently audit a completed Deep1B 100M Mac queue."""

import array
import csv
import hashlib
import json
import math
import platform
import re
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path


ROWS = 100_000_000
COLS = 96
K = 30
INPUT_SHA = "259e5ed58e0218790bec8e8514c011f39bfd839c012d8d818d9106773ffeac94"
ARCHIVE_SHA = "ae37cd4f3638ec59d515456e5c6e0c1bf6d38de8fba05414aab471a0abd76e00"
STAGES = (
    "smoke_fullgraph", "pca_cpu1", "pca_cpu8", "pca_cpu20",
    "pca_cpu28", "pca_metal", "knn_cpu20", "tsne_affinity",
    "tsne_cpu20", "umap_membership", "umap_fuzzy", "umap_metal",
    "umap_cpu20", "umap_cpu1", "leiden_cpu",
)
LAYOUT = {"pca_cpu1", "pca_cpu8", "pca_cpu20", "pca_cpu28",
          "pca_metal", "tsne_cpu20", "umap_metal", "umap_cpu20",
          "umap_cpu1"}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha256_file(path, check_finite=False):
    digest = hashlib.sha256()
    finite_count = 0
    with path.open("rb") as stream:
        while block := stream.read(4 * 250_000):
            digest.update(block)
            if check_finite:
                require(len(block) % 4 == 0, "Incomplete float32 block")
                values = array.array("f")
                values.frombytes(block)
                require(all(math.isfinite(x) for x in values),
                        f"Nonfinite layout: {path}")
                finite_count += len(values)
    return digest.hexdigest(), finite_count


def source_lock(root, queue):
    locked = (queue / "sources.lock").read_bytes()
    require(locked == (queue / "sources.current").read_bytes(),
            "Source lock changed during 100M execution")
    for line in locked.decode().splitlines():
        expected, path = line.split(None, 1)
        source = Path(path)
        if not source.is_absolute():
            source = root / source
        observed, _ = sha256_file(source)
        require(observed == expected, f"Locked source changed: {path}")
    return hashlib.sha256(locked).hexdigest()


def check_identity(root, queue):
    identity = dict(line.split("=", 1) for line in
                    (queue / "identity.txt").read_text().splitlines())
    require(identity.get("input_sha256") == INPUT_SHA and
            identity.get("archive_sha256") == ARCHIVE_SHA and
            re.fullmatch(r"disk[0-9]+", identity.get("physical_disk", "")),
            "Queue input, package, or disk identity changed")
    source_lock_sha = source_lock(root, queue)
    campaign = root.parent
    input_path = (campaign / "data/BigANN/deep/mod10-100000000" /
                  "base.mod10.100000000.fbin")
    archive = (campaign / "candidates/mac-benchmark-integration-20261102-v3" /
               "fastEmbedR_0.1.tar.gz")
    require(input_path.stat().st_size == 8 + ROWS * COLS * 4,
            "Subset file size changed")
    with input_path.open("rb") as stream:
        require(struct.unpack("<ii", stream.read(8)) == (ROWS, COLS),
                "Subset dimensions changed")
    require(sha256_file(input_path)[0] == INPUT_SHA and
            sha256_file(archive)[0] == ARCHIVE_SHA,
            "Subset or package archive changed")
    full = campaign / "data/BigANN/deep/1000000000/base.1000000000.fbin"
    require(not full.exists(), "Retired 1B source unexpectedly returned")
    retired = json.loads((campaign / "deep1b-100m-v1" /
                          "full_source_retirement.json").read_text())
    require(retired.get("status") == "full_source_removed",
            "Full-source retirement evidence is missing")
    return source_lock_sha


def guard_evidence(queue, stage):
    stage_root = queue / stage
    guard = json.loads((stage_root / "guard.json").read_text())
    baseline = guard.get("baseline", {})
    final = guard.get("final", {})
    require(guard.get("status") == "passed" and
            guard.get("worker_exit_code") == 0 and
            guard.get("free_pct_min", 0) >= 50 and
            final.get("swapouts") == baseline.get("swapouts") and
            all((stage_root / name).stat().st_size > 0 for name in
                ("disk_before.txt", "disk_after.txt", "time.txt",
                 "worker.log")),
            f"Stage guard or resource evidence failed: {stage}")
    time_text = (stage_root / "time.txt").read_text()
    peak = re.search(r"^\s*([0-9]+)\s+maximum resident set size\s*$",
                     time_text, re.M)
    return guard["free_pct_min"], int(peak.group(1)) if peak else None


def stage_files(root, stage):
    case = root / "cases" / stage
    paths = [case / "result.rds"]
    if stage in LAYOUT:
        paths.append(case / ("scores.f32" if stage.startswith("pca_")
                             else "layout.f32"))
    elif stage == "knn_cpu20":
        paths.extend(case / ("knn" + suffix) for suffix in
                     (".indices.u32", ".distances.f32"))
    elif stage in ("tsne_affinity", "umap_fuzzy"):
        prefix = "affinity" if stage == "tsne_affinity" else "fuzzy"
        paths.extend(case / (prefix + suffix) for suffix in
                     (".offsets.u64", ".indices.u32", ".weights.f32"))
    elif stage == "umap_membership":
        paths.append(root / "cases/knn_cpu20/knn.weights.f32")
    elif stage == "leiden_cpu":
        paths.append(case / "communities.u32")
    return paths


def check_graph(case, prefix):
    offsets = case / (prefix + ".offsets.u64")
    indices = case / (prefix + ".indices.u32")
    weights = case / (prefix + ".weights.f32")
    require(offsets.stat().st_size == (ROWS + 1) * 8 and
            indices.stat().st_size == weights.stat().st_size and
            indices.stat().st_size % 4 == 0,
            f"CSR graph byte counts changed: {prefix}")
    edges = indices.stat().st_size // 4
    previous = -1
    count = 0
    with offsets.open("rb") as stream:
        while block := stream.read(8 * 131_072):
            values = array.array("Q")
            values.frombytes(block)
            for value in values:
                require(previous <= value <= edges,
                        f"CSR offsets are not ordered: {prefix}")
                if count == 0:
                    require(value == 0, "CSR first offset changed")
                previous = value
                count += 1
    require(count == ROWS + 1 and previous == edges and
            0 < edges <= 2 * ROWS * K,
            f"CSR graph offsets or edge count changed: {prefix}")
    return edges


def audit(root):
    require(platform.system() == "Darwin" and sys.byteorder == "little",
            "This full 100M audit runs on the little-endian Mac")
    require(str(root).startswith(
            "/Users/silvanopiazza/Documents/Stefano/"),
            "100M audit source leaves Stefano")
    queue = root / "queue100m"
    require((queue / "queue.exit").read_text().strip() == "0",
            "100M queue is not complete")
    with (queue / "status.csv").open(newline="") as stream:
        status = list(csv.DictReader(stream))
    require([(row["stage"], row["status"]) for row in status] ==
            [(stage, "success") for stage in STAGES] +
            [("queue", "success")], "100M stages are incomplete")
    source_lock_sha = check_identity(root, queue)
    stage_rows = []
    file_rows = []
    for row in status[:-1]:
        stage = row["stage"]
        free_min, peak_rss = guard_evidence(queue, stage)
        for path in stage_files(root, stage):
            require(path.is_file(), f"Stage output is missing: {path}")
            size = path.stat().st_size
            finite = stage in LAYOUT and path.suffix == ".f32"
            if finite:
                require(size == ROWS * 2 * 4,
                        f"Layout byte count changed: {path}")
            elif stage == "knn_cpu20" and path.suffix in (".u32", ".f32"):
                require(size == ROWS * K * 4,
                        f"KNN byte count changed: {path}")
            elif stage == "umap_membership" and path.suffix == ".f32":
                require(size == ROWS * K * 4,
                        "Directed membership byte count changed")
            elif stage == "leiden_cpu" and path.suffix == ".u32":
                require(size == ROWS * 4,
                        "Leiden membership byte count changed")
            digest, count = sha256_file(path, finite)
            if finite:
                require(count == ROWS * 2,
                        f"Layout element count changed: {path}")
            file_rows.append((stage, str(path), size, digest, finite))
        graph_edges = None
        if stage in ("tsne_affinity", "umap_fuzzy"):
            graph_edges = check_graph(root / "cases" / stage,
                                      "affinity" if stage ==
                                      "tsne_affinity" else "fuzzy")
        stage_rows.append((stage, int(row["seconds"]), free_min,
                           peak_rss, graph_edges))
    output = root / "postprocess-audit-v1"
    require(not output.exists(), "Postprocess audit output already exists")
    output.mkdir()
    with (output / "stages.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("stage", "wall_seconds", "free_pct_min",
                         "peak_rss_bytes", "graph_edges"))
        writer.writerows(stage_rows)
    with (output / "files.sha256.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("stage", "path", "bytes", "sha256",
                         "full_finite_scan"))
        writer.writerows(file_rows)
    (output / "audit.json").write_text(json.dumps({
        "status": "passed", "rows": ROWS, "columns": COLS, "neighbors": K,
        "input_sha256": INPUT_SHA, "archive_sha256": ARCHIVE_SHA,
        "source_lock_sha256": source_lock_sha,
        "stage_count": len(STAGES), "file_count": len(file_rows),
        "completed_utc": datetime.now(timezone.utc).isoformat(),
    }, indent=2, sort_keys=True) + "\n")
    print(f"Verified {len(STAGES)} stages and {len(file_rows)} files")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: audit_deep1b_100m_mac_v1.py RUN_ROOT")
    audit(Path(sys.argv[1]).resolve())
