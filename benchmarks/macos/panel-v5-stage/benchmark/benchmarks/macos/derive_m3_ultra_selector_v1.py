#!/usr/bin/env python3
"""Summarize audited resident Mac CPU/Metal choices; do not fit a crossover."""

import csv
import hashlib
import json
import math
import statistics
import sys
from pathlib import Path


DATASETS = (
    "COIL20", "MetRef", "USPS", "Macosko2015_retina", "MNIST",
    "FashionMNIST", "TabulaMuris", "mass41", "flow18",
    "FlowRepository_FR-FCM-ZYRM_files", "imagenet",
)
FULL = (
    "fastEmbedR_pca", "fastEmbedR_tsne_full",
    "fastEmbedR_umap_fuzzy_full", "fastEmbedR_umap_binary_full",
)
KNN = (
    "fastEmbedR_tsne_knn", "fastEmbedR_umap_fuzzy_knn",
    "fastEmbedR_umap_binary_knn",
)
SEEDS = (4, 17, 42)
THREADS = (1, 4, 8, 12, 20, 28)
FILES = (
    "input_postflight.json", "panel_audit.json", "benchmark_runs.csv",
    "quality_speed_summary.csv", "metal_paired_quality_speed.csv",
    "global_knn_recall_audit.csv", "source_identity.txt",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def csv_rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def truth(value):
    require(value in ("TRUE", "FALSE"), f"Invalid Boolean: {value}")
    return value == "TRUE"


def number(value, label):
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Invalid {label}: {value}") from exc
    require(math.isfinite(result), f"Nonfinite {label}")
    return result


def identity(path):
    lines = path.read_text().splitlines()
    return dict(line.split("=", 1) for line in lines if "=" in line)


def observations(queue_root, campaign_root):
    status = csv_rows(queue_root / "status.csv")
    expected = [(name, "success", f"{queue_root.name}_{name}")
                for name in DATASETS]
    actual = [(row.get("dataset"), row.get("status"), row.get("run_id"))
              for row in status]
    require(actual in (expected,
                       expected + [("queue", "success", queue_root.name)]),
            "Queue is incomplete or has unexpected status rows")
    require((queue_root / "sources.lock").read_bytes() ==
            (queue_root / "sources.current").read_bytes(),
            "Queue source lock changed")
    package_commit = (queue_root / "package_commit.lock").read_text().strip()
    benchmark_commit = (queue_root / "benchmark_commit.lock").read_text().strip()
    result = []
    hashes = []
    for dataset in DATASETS:
        run_id = f"{queue_root.name}_{dataset}"
        root = campaign_root / "results" / "m3-ultra-panel-v1" / run_id
        require(root.is_dir(), f"Missing run: {run_id}")
        for name in FILES:
            path = root / name
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            hashes.append((dataset, name, digest))
        source = identity(root / "source_identity.txt")
        require(source.get("package_commit") == package_commit and
                source.get("benchmark_commit") == benchmark_commit and
                bool(source.get("installed_dll_sha256")),
                f"Source identity mismatch: {dataset}")
        input_report = json.loads((root / "input_postflight.json").read_text())
        panel = json.loads((root / "panel_audit.json").read_text())
        require(input_report.get("status") == "inputs_verified" and
                [row.get("dataset") for row in input_report.get("inputs", [])]
                == [dataset] and panel.get("execution_status") == "passed" and
                panel.get("dataset") == dataset and
                panel.get("observed_arms") == 147,
                f"Audit failed: {dataset}")
        runs = csv_rows(root / "benchmark_runs.csv")
        require(len(runs) == 147 and
                all(row.get("dataset") == dataset and
                    row.get("status") == "success" for row in runs),
                f"Incomplete run table: {dataset}")
        n_values = {number(row.get("n"), "n") for row in runs}
        p_values = {number(row.get("p"), "p") for row in runs}
        require(len(n_values) == len(p_values) == 1 and
                next(iter(n_values)) > 0 and next(iter(p_values)) > 0,
                f"Inconsistent shape: {dataset}")
        n, p = int(next(iter(n_values))), int(next(iter(p_values)))
        summary = csv_rows(root / "quality_speed_summary.csv")
        pairs = csv_rows(root / "metal_paired_quality_speed.csv")
        recall = csv_rows(root / "global_knn_recall_audit.csv")
        require(len(summary) == 7 and len(pairs) == 21 and len(recall) == 63,
                f"Incomplete quality evidence: {dataset}")
        require({row.get("method") for row in summary} == set(FULL + KNN),
                f"Unexpected methods: {dataset}")
        require(len({row.get("method") for row in summary}) == 7,
                f"Duplicate methods: {dataset}")
        for row in summary:
            method = row["method"]
            selected = [pair for pair in pairs if pair.get("method") == method]
            seeds = {int(pair["seed"]) for pair in selected}
            require(len(selected) == 3 and seeds == set(SEEDS),
                    f"Missing paired seeds: {dataset}/{method}")
            thread = int(row["best_cpu_threads"])
            require(thread in THREADS and all(
                int(pair["best_cpu_threads"]) == thread for pair in selected),
                f"CPU thread mismatch: {dataset}/{method}")
            ratios = [number(pair.get("cpu_over_metal"), "paired ratio")
                      for pair in selected]
            require(all(ratio > 0 for ratio in ratios), "Invalid speed ratio")
            quality = all(truth(pair.get("quality_pass")) for pair in selected)
            speed = all(ratio >= 1.2 for ratio in ratios)
            require(all(truth(pair.get("speed_pass")) == (ratio >= 1.2)
                        for pair, ratio in zip(selected, ratios)) and
                    truth(row.get("quality_pass")) == quality and
                    truth(row.get("speed_pass")) == speed and
                    truth(row.get("quality_speed_gate")) == (quality and speed)
                    and math.isclose(number(row.get("median_ratio"),
                                            "median ratio"),
                                     statistics.median(ratios), rel_tol=1e-9),
                    f"Paired summary mismatch: {dataset}/{method}")
            scope = row.get("timing_scope")
            if method in KNN:
                require(scope == "embedding_from_precomputed_knn" and
                        row.get("knn_recall_status") ==
                        "precomputed_knn_outside_timing" and
                        row.get("end_to_end_speed_gate") in ("NA", "") and
                        row.get("recall_qualified_end_to_end_gate") in
                        ("NA", ""), f"KNN scope mismatch: {dataset}/{method}")
                continue
            require(scope == ("pca_only" if method == "fastEmbedR_pca"
                              else "full_pipeline"),
                    f"Timing scope mismatch: {dataset}/{method}")
            recall_status = row.get("knn_recall_status")
            require(recall_status == ("not_applicable" if method ==
                    "fastEmbedR_pca" else "sampled_exact_reference_pass") or
                    (method != "fastEmbedR_pca" and recall_status ==
                     "sampled_exact_reference_fail"),
                    f"Recall status invalid: {dataset}/{method}")
            recall_ok = recall_status in ("not_applicable",
                                          "sampled_exact_reference_pass")
            passed = quality and speed
            require(truth(row.get("end_to_end_speed_gate")) == passed,
                    f"End-to-end gate mismatch: {dataset}/{method}")
            expected_gate = "FALSE" if not passed else (
                "TRUE" if recall_ok else "NA")
            require(row.get("recall_qualified_end_to_end_gate") ==
                    expected_gate, f"Recall gate mismatch: {dataset}/{method}")
            result.append({
                "dataset": dataset, "n": n, "p": p, "method": method,
                "best_cpu_threads": thread,
                "cpu_over_metal_min": min(ratios),
                "cpu_over_metal_median": statistics.median(ratios),
                "cpu_over_metal_max": max(ratios),
                "quality_pass": quality, "recall_status": recall_status,
                "speed_pass_all_seeds": speed,
                "selected_backend": "metal" if passed and recall_ok else "cpu",
                "evidence_dir": str(root),
            })
    require(len(result) == 44, "Incomplete selector observations")
    return result, hashes


def main():
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: derive_m3_ultra_selector_v1.py QUEUE_ROOT CAMPAIGN_ROOT")
    queue_root, campaign_root = (Path(arg).resolve() for arg in sys.argv[1:])
    try:
        rows, hashes = observations(queue_root, campaign_root)
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Selector evidence rejected: {exc}") from exc
    with (queue_root / "selector_observations.csv").open("w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    with (queue_root / "selector_inputs.sha256").open("w") as out:
        for dataset, name, digest in hashes:
            out.write(f"{digest}  {dataset}/{name}\n")
    print("Saved 44 audited dataset/method observations; no crossover fitted")


if __name__ == "__main__":
    main()
