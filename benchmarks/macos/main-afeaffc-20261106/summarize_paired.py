#!/usr/bin/env python3
"""Describe matched CPU and Metal cases without setting quality gates."""

import argparse
from collections import Counter
import json
import math
from pathlib import Path


def lane(metrics):
    if metrics.get("backend") == "metal":
        return "metal1"
    if metrics.get("backend") == "cpu" and metrics.get("cores") in (1, 4):
        return "cpu" + str(metrics["cores"])
    return None


def identity(metrics):
    return tuple(metrics.get(key) for key in
                 ("dataset", "method", "dimensions", "seed",
                  "repetition"))


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def elapsed(metrics):
    stages = ("graph_seconds", "fit_seconds")
    values = [metrics.get(stage) for stage in stages]
    return sum(values) if all(finite(value) and value >= 0
                              for value in values) else None


def quality_delta(cpu, metal, method):
    left = cpu.get("quality", {})
    right = metal.get("quality", {})
    names = (("trustworthiness", "label_accuracy")
             if method in ("t-SNE", "UMAP") else
             ("ari", "modularity") if method in
             ("Leiden", "Louvain") else ())
    if names:
        return {name: right[name] - left[name] for name in names
                if finite(left.get(name)) and finite(right.get(name))}
    a = left.get("singular_values")
    b = right.get("singular_values")
    if (isinstance(a, list) and isinstance(b, list) and
            len(a) == len(b) and a and all(
                finite(x) for x in a + b)):
        return {"singular_relative_max": max(
            abs(y - x) / max(abs(x), 1e-12)
            for x, y in zip(a, b))}
    return {}


def compare(cpu, metal):
    method = cpu["metrics"]["method"]
    cpu_seconds = elapsed(cpu["metrics"])
    metal_seconds = elapsed(metal["metrics"])
    cpu_rss = cpu["run"].get("peak_rss_bytes")
    metal_rss = metal["run"].get("peak_rss_bytes")
    source_fields = ("source_sha256", "dll_sha256", "input_sha256")
    source_match = all(cpu["run"].get(key) == metal["run"].get(key)
                       for key in source_fields)
    return {"key": list(identity(cpu["metrics"])),
            "source_match": source_match,
            "quality_delta_metal_minus_cpu": quality_delta(
                cpu["metrics"], metal["metrics"], method),
            "fit_speedup_cpu_over_metal":
                cpu_seconds / metal_seconds if cpu_seconds is not None and
                metal_seconds is not None and metal_seconds > 0 else None,
            "peak_rss_ratio_metal_over_cpu":
                metal_rss / cpu_rss if finite(cpu_rss) and cpu_rss > 0 and
                finite(metal_rss) else None}


def summarize(root):
    grouped = {}
    skipped = Counter()
    for result in sorted((root / "results").iterdir()):
        run_path = result / "run.json"
        metrics_path = result / "metrics.json"
        if not run_path.is_file() or not metrics_path.is_file():
            skipped["incomplete"] += 1
            continue
        run = json.loads(run_path.read_text())
        if run.get("status") != "completed" or not run.get(
                "cleanup_clear"):
            skipped["failed"] += 1
            continue
        metrics = json.loads(metrics_path.read_text())
        label = lane(metrics)
        if label is None:
            skipped["other_lane"] += 1
            continue
        key = identity(metrics)
        if label in grouped.setdefault(key, {}):
            skipped["duplicate"] += 1
            continue
        grouped[key][label] = {"run": run, "metrics": metrics}
    pairs = []
    for key, lanes in grouped.items():
        if "metal1" not in lanes:
            continue
        for cpu_lane in ("cpu1", "cpu4"):
            if cpu_lane in lanes:
                pairs.append({"cpu_lane": cpu_lane,
                              **compare(lanes[cpu_lane], lanes["metal1"])})
    pairs.sort(key=lambda row: (row["key"], row["cpu_lane"]))
    by_method = Counter(row["key"][1] for row in pairs)
    mismatches = [row["key"] for row in pairs if not row["source_match"]]
    return {"paired_comparisons": len(pairs),
            "by_method": dict(by_method),
            "source_mismatches": mismatches,
            "skipped": dict(skipped), "pairs": pairs}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("panel_root", type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.panel_root), indent=2,
                     sort_keys=True))


if __name__ == "__main__":
    main()
