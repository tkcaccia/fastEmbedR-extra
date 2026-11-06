#!/usr/bin/env python3
"""Check M3 Ultra panel coverage and resource gates after one dataset run."""

import csv
import json
import math
import sys
from pathlib import Path


CPU = (
    "fastEmbedR_pca_cpu",
    "fastEmbedR_tsne_cpu_full",
    "fastEmbedR_tsne_cpu_knn",
    "fastEmbedR_umap_cpu_fuzzy_full",
    "fastEmbedR_umap_cpu_fuzzy_knn",
    "fastEmbedR_umap_cpu_binary_full",
    "fastEmbedR_umap_cpu_binary_knn",
)
THREADS = (1, 4, 8, 12, 20, 28)
SEEDS = (4, 17, 42)
ROWS = {
    "COIL20": 1440,
    "USPS": 11000,
    "MNIST": 70000,
    "FashionMNIST": 70000,
    "MetRef": 873,
    "mass41": 965282,
    "flow18": 1000021,
    "imagenet": 1281167,
    "FlowRepository_FR-FCM-ZYRM_files": 5220347,
    "TabulaMuris": 100102,
    "Macosko2015_retina": 44808,
}


def numeric(row, name):
    try:
        number = float(row.get(name, ""))
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def expected_keys():
    for method in CPU:
        for thread in THREADS:
            for seed in SEEDS:
                yield (method, thread, seed)
        metal = method.replace("_cpu", "_metal")
        for seed in SEEDS:
            yield (metal, max(THREADS), seed)


def read_rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def read_identity(path):
    if not path.is_file():
        return {}
    return dict(line.split("=", 1) for line in path.read_text().splitlines()
                if "=" in line)


def inspect(path, dataset):
    issues = []
    rows = read_rows(path)
    identity = read_identity(path.parent / "source_identity.txt")
    fields = {
        "fastEmbedR_commit": "package_commit",
        "fastEmbedR_version": "installed_version",
        "fastEmbedR_dll_sha256": "installed_dll_sha256",
        "benchmark_commit": "benchmark_commit",
    }
    if any(not identity.get(source) for source in fields.values()):
        issues.append("Incomplete Mac source or binary identity")
    observed = {}
    for row in rows:
        try:
            key = (row["method"], int(row["requested_threads"]),
                   int(row["seed"]))
        except (KeyError, ValueError):
            issues.append("Malformed method, thread or seed")
            continue
        if key in observed:
            issues.append(f"Duplicate arm: {key}")
        observed[key] = row
        if row.get("dataset") != dataset:
            issues.append(f"Wrong dataset in arm: {key}")
        if row.get("status") != "success":
            issues.append(f"Unsuccessful arm: {key}")
        for column, source in fields.items():
            if not identity.get(source) or row.get(column) != identity[source]:
                issues.append(f"Source or binary identity mismatch: {key}")
        backend = "metal" if "_metal" in key[0] else "cpu"
        if row.get("actual_backend") != backend:
            issues.append(f"Backend mismatch: {key}")
        if backend == "metal" and "_full" in key[0]:
            if "metal" not in row.get("nn_backend", "").lower():
                issues.append(f"Metal KNN backend unverified: {key}")
        if backend == "metal":
            allocation = numeric(row, "metal_allocated_bytes_observed")
            if allocation is None or allocation <= 0:
                issues.append(f"Metal allocation unmeasured: {key}")
            scope = ("pca_sampled_currentAllocatedSize" if
                     "_pca_" in key[0] else
                     "optimizer_sampled_currentAllocatedSize")
            if row.get("metal_allocation_scope") != scope:
                issues.append(f"Metal allocation scope missing: {key}")
        if numeric(row, "n") != ROWS[dataset]:
            issues.append(f"Wrong row count: {key}")
        runtime = numeric(row, "total_runtime_sec")
        if runtime is None or runtime <= 0:
            issues.append(f"Invalid runtime: {key}")
        free = numeric(row, "mac_system_free_pct_min")
        if free is None or free < 50:
            issues.append(f"Memory gate failed: {key}")
        if row.get("mac_guard_status") != "passed":
            issues.append(f"Active Mac memory guard failed: {key}")
        evidence = row.get("mac_guard_evidence_file", "")
        if not evidence or not Path(evidence).is_file():
            issues.append(f"Missing active Mac guard evidence: {key}")
        else:
            try:
                guard = json.loads(Path(evidence).read_text())
                valid = (guard.get("status") == "passed" and
                         guard.get("worker_exit_code") == 0 and
                         guard.get("free_pct_min", 0) >= 50 and
                         guard["final"]["pageouts"] >=
                         guard["baseline"]["pageouts"] and
                         guard["final"]["swapouts"] ==
                         guard["baseline"]["swapouts"])
                if not valid:
                    issues.append(f"Active Mac guard evidence failed: {key}")
            except (OSError, ValueError, KeyError, TypeError):
                issues.append(f"Invalid active Mac guard evidence: {key}")
        pageouts = numeric(row, "mac_system_pageouts_delta")
        if pageouts is None or pageouts < 0:
            issues.append(f"mac_system_pageouts_delta missing: {key}")
        for field in ("mac_system_swapouts_delta", "process_swaps"):
            if numeric(row, field) != 0:
                issues.append(f"{field} gate failed: {key}")
        for field in ("layout_file", "plot_file"):
            target = row.get(field, "")
            if not target or not Path(target).is_file():
                issues.append(f"Missing {field}: {key}")
        device = row.get("mac_disk_device", "")
        if not device.startswith("disk"):
            issues.append(f"Physical disk device unverified: {key}")
        for field in ("mac_disk_before_file", "mac_disk_after_file"):
            target = row.get(field, "")
            if not target or not Path(target).is_file() or (
                    Path(target).stat().st_size == 0):
                issues.append(f"Missing physical disk snapshot {field}: {key}")
    expected = set(expected_keys())
    for key in sorted(expected - observed.keys()):
        issues.append(f"Missing arm: {key}")
    for key in sorted(observed.keys() - expected):
        issues.append(f"Unexpected arm: {key}")
    precompute = path.parent / "precompute_manifest.csv"
    if not precompute.is_file():
        issues.append("Missing precompute manifest")
    else:
        pre = read_rows(precompute)
        if len(pre) != 1 or pre[0].get("status") != "success":
            issues.append("Precompute did not succeed")
    schedule = path.parent / "execution_schedule.csv"
    if not schedule.is_file():
        issues.append("Missing execution schedule")
    else:
        planned = read_rows(schedule)
        if len(planned) != len(expected) or any(
                row.get("status") != "success" for row in planned):
            issues.append("Execution schedule has missing or failed arms")
    return rows, observed, issues


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ROWS:
        raise SystemExit("usage: audit_m3_ultra_panel_v1.py RUNS_CSV DATASET")
    path, dataset = Path(sys.argv[1]), sys.argv[2]
    rows, observed, issues = inspect(path, dataset)
    result = {
        "dataset": dataset,
        "observed_arms": len(rows),
        "expected_arms": len(tuple(expected_keys())),
        "execution_status": "passed" if not issues else "failed",
        "issues": issues,
        "speed_status": "see quality_speed_summary.csv after quality audit",
        "quality_status": "requires saved-layout quality audit",
        "gpu_allocation_status": (
            "PCA and optimizer device samples required; "
            "whole-pipeline GPU peak requires Xcode trace"
        ),
        "disk_status": (
            "whole-device before/after snapshots required; "
            "not per-worker read/write attribution"
        ),
    }
    print(json.dumps(result, indent=2))
    return 0 if not issues else 1


if __name__ == "__main__":
    raise SystemExit(main())
