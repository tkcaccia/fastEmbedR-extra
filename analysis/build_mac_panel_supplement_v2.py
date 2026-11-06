#!/usr/bin/env python3
"""Build a Mac per-dataset JSS table from a fully audited panel."""

import csv
import importlib.util
import math
import os
import statistics
import sys
from pathlib import Path


SELECTOR = (Path(__file__).resolve().parents[1] / "benchmarks" /
            "macos/panel-v6-stage/benchmark/benchmarks/macos" /
            "derive_m3_ultra_selector_v2.py")
if os.environ.get("FASTEMBEDR_MAC_SELECTOR"):
    SELECTOR = Path(os.environ["FASTEMBEDR_MAC_SELECTOR"])
METHODS = {
    "fastEmbedR_pca": ("PCA", "fastEmbedR_pca_cpu",
                       "fastEmbedR_pca_metal"),
    "fastEmbedR_tsne_full": ("t-SNE full", "fastEmbedR_tsne_cpu_full",
                             "fastEmbedR_tsne_metal_full"),
    "fastEmbedR_tsne_knn": ("t-SNE KNN", "fastEmbedR_tsne_cpu_knn",
                            "fastEmbedR_tsne_metal_knn"),
    "fastEmbedR_umap_fuzzy_full": (
        "UMAP fuzzy full", "fastEmbedR_umap_cpu_fuzzy_full",
        "fastEmbedR_umap_metal_fuzzy_full"),
    "fastEmbedR_umap_fuzzy_knn": (
        "UMAP fuzzy KNN", "fastEmbedR_umap_cpu_fuzzy_knn",
        "fastEmbedR_umap_metal_fuzzy_knn"),
    "fastEmbedR_umap_binary_full": (
        "UMAP binary full", "fastEmbedR_umap_cpu_binary_full",
        "fastEmbedR_umap_metal_binary_full"),
    "fastEmbedR_umap_binary_knn": (
        "UMAP binary KNN", "fastEmbedR_umap_cpu_binary_knn",
        "fastEmbedR_umap_metal_binary_knn"),
}
FIELDS = ("dataset", "n", "p", "method", "timing_scope",
          "cpu_threads", "cpu_selection_qualified", "cpu_selection_basis",
          "cpu_median_seconds", "metal_median_seconds",
          "median_paired_cpu_over_metal", "quality_pass",
          "speed_pass_all_seeds", "knn_recall_status",
          "quality_speed_gate", "recall_qualified_end_to_end_gate")


def selector_module():
    spec = importlib.util.spec_from_file_location("mac_panel_selector", SELECTOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value, label):
    result = float(value)
    require(math.isfinite(result) and result > 0,
            f"Invalid {label}: {value}")
    return result


def time_rows(runs, method, backend, threads):
    selected = [row for row in runs if row["method"] == method]
    if backend == "cpu":
        selected = [row for row in selected if
                    int(row["requested_threads"]) == threads]
    require(len(selected) == 3 and
            {int(row["seed"]) for row in selected} == {4, 17, 42} and
            all(row["actual_backend"] == backend and
                row["status"] == "success" for row in selected),
            f"Missing paired timings: {method}/{backend}")
    return [number(row["total_runtime_sec"], "runtime")
            for row in selected]


def dataset_rows(root, dataset, audit=None):
    if audit is None:
        audit = root
    with (root / "benchmark_runs.csv").open(newline="") as stream:
        runs = list(csv.DictReader(stream))
    with (audit / "quality_speed_summary.csv").open(newline="") as stream:
        summary = list(csv.DictReader(stream))
    require(len(runs) == 147 and len(summary) == 7,
            f"Incomplete dataset: {dataset}")
    n = {int(row["n"]) for row in runs}
    p = {int(row["p"]) for row in runs}
    require(len(n) == len(p) == 1, f"Shape changed: {dataset}")
    result = []
    for item in summary:
        method = item["method"]
        label, cpu_method, metal_method = METHODS[method]
        threads = int(item["best_cpu_threads"])
        cpu = time_rows(runs, cpu_method, "cpu", threads)
        metal = time_rows(runs, metal_method, "metal", threads)
        ratio = number(item["median_ratio"], "paired speed ratio")
        result.append(dict(zip(FIELDS, (
            dataset, next(iter(n)), next(iter(p)), label,
            item["timing_scope"], threads,
            item.get("cpu_selection_qualified", "TRUE"),
            item.get("cpu_selection_basis", "qualified_fastest"),
            statistics.median(cpu), statistics.median(metal), ratio,
            item["quality_pass"], item["speed_pass"],
            item["knn_recall_status"], item["quality_speed_gate"],
            item["recall_qualified_end_to_end_gate"]))))
    require(len({row["method"] for row in result}) == 7,
            f"Duplicate method: {dataset}")
    return result


def tex_escape(value):
    return str(value).replace("_", "\\_").replace("&", "\\&")


def write_tex(rows, path):
    lines = [
        r"\begin{longtable}{llrrrrll}",
        r"\caption{Audited Apple M3 Ultra results for each dataset and "
        r"method. Times are median seconds over three matched seeds. "
        r"The ratio is the median of paired CPU/Metal ratios, not the "
        r"ratio of displayed medians. KNN rows exclude neighbor-search "
        r"time. B marks a quality-qualified CPU baseline; Q and S are "
        r"all-seed quality and 1.2-fold speed gates; "
        r"R is sampled "
        r"full-KNN recall (NA for PCA or precomputed KNN).}"
        r"\label{tab:mac-panel}" + "\\\\",
        r"\toprule",
        r"Dataset & Method & $n$ & CPU threads & CPU (s) & Metal (s) & "
        r"CPU/Metal & B / Q / S / R " + "\\\\",
        r"\midrule",
        r"\endfirsthead",
        r"\toprule",
        r"Dataset & Method & $n$ & CPU threads & CPU (s) & Metal (s) & "
        r"CPU/Metal & B / Q / S / R " + "\\\\",
        r"\midrule",
        r"\endhead",
    ]
    for row in rows:
        baseline = ("Y" if row["cpu_selection_qualified"] == "TRUE"
                    else "N")
        quality = "Y" if row["quality_pass"] == "TRUE" else "N"
        speed = "Y" if row["speed_pass_all_seeds"] == "TRUE" else "N"
        recall = row["knn_recall_status"]
        recall = ("Y" if recall == "sampled_exact_reference_pass" else
                  "N" if recall == "sampled_exact_reference_fail" else "NA")
        lines.append(" & ".join((
            tex_escape(row["dataset"]), tex_escape(row["method"]),
            str(row["n"]), str(row["cpu_threads"]),
            f'{row["cpu_median_seconds"]:.3f}',
            f'{row["metal_median_seconds"]:.3f}',
            f'{row["median_paired_cpu_over_metal"]:.2f}',
            f"{baseline} / {quality} / {speed} / {recall}")) + " \\\\")
    lines.extend((r"\bottomrule", r"\end{longtable}"))
    path.write_text("\n".join(lines) + "\n")


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: script.py QUEUE_ROOT CAMPAIGN_ROOT OUTPUT_PREFIX")
    queue, campaign, output = (Path(arg).resolve() for arg in sys.argv[1:])
    require(not output.with_suffix(".csv").exists() and
            not output.with_suffix(".tex").exists(),
            "Mac supplement outputs already exist")
    selector = selector_module()
    selector.observations(queue, campaign)
    with (queue / "status.csv").open(newline="") as stream:
        status = {row["dataset"]: row for row in csv.DictReader(stream)}
    rows = []
    for dataset in selector.DATASETS:
        state = status[dataset]
        root = (campaign / "results/m3-ultra-panel-v1" /
                state["run_id"])
        audit = Path(state["audit_dir"]) if state["audit_dir"] else root
        rows.extend(dataset_rows(root, dataset, audit))
    require(len(rows) == 77, "Incomplete per-dataset Mac table")
    with output.with_suffix(".csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    write_tex(rows, output.with_suffix(".tex"))
    print("Wrote 77 audited Mac dataset/method observations")


if __name__ == "__main__":
    main()
