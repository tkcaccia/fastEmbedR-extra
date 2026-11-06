#!/usr/bin/env python3
"""Summarize all audited Mac CPU thread settings across 11 datasets."""

import csv
import importlib.util
import math
import statistics
import sys
from pathlib import Path


REPORT = Path(__file__).with_name("build_mac_panel_supplement_v2.py")
THREADS = (1, 4, 8, 12, 20, 28)
SEEDS = (4, 17, 42)
FIELDS = ("dataset", "n", "p", "method", "timing_scope", "threads",
          "median_seconds", "paired_speedup_vs_cpu1",
          "median_peak_ram_gb", "quality_pass_all_seeds",
          "recall_pass_all_seeds", "valid_for_cpu_selection")


def require(ok, message):
    if not ok:
        raise ValueError(message)


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def csv_rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def positive(value, name):
    result = float(value)
    require(math.isfinite(result) and result > 0,
            f"Invalid {name}: {value}")
    return result


def selected(runs, method, thread):
    found = [row for row in runs if row["method"] == method and
             row["actual_backend"] == "cpu" and
             int(row["requested_threads"]) == thread]
    require(len(found) == 3 and
            {int(row["seed"]) for row in found} == set(SEEDS) and
            all(row["status"] == "success" for row in found),
            f"Incomplete Mac CPU timings: {method}/{thread}")
    return {int(row["seed"]): row for row in found}


def dataset_rows(root, audit, dataset, report):
    runs = csv_rows(root / "benchmark_runs.csv")
    grid = csv_rows(audit / "cpu_quality_grid.csv")
    require(len(runs) == 147 and len(grid) == 42,
            f"Incomplete Mac CPU grid: {dataset}")
    n = {int(row["n"]) for row in runs}
    p = {int(row["p"]) for row in runs}
    require(len(n) == len(p) == 1, f"Shape changed: {dataset}")
    result = []
    for _, (label, cpu_method, _) in report.METHODS.items():
        baseline = selected(runs, cpu_method, 1)
        baseline_time = {seed: positive(row["total_runtime_sec"],
                                        "CPU baseline time")
                         for seed, row in baseline.items()}
        for thread in THREADS:
            current = selected(runs, cpu_method, thread)
            quality = [row for row in grid if row["method"] == cpu_method
                       and int(row["threads"]) == thread]
            require(len(quality) == 1, "CPU quality grid has duplicates")
            item = quality[0]
            flags = [item[name] for name in
                     ("quality_pass_all_seeds", "recall_pass_all_seeds",
                      "valid_for_cpu_selection")]
            require(all(flag in ("TRUE", "FALSE") for flag in flags),
                    "CPU quality grid has an invalid flag")
            seconds = {seed: positive(row["total_runtime_sec"],
                                      "CPU runtime")
                       for seed, row in current.items()}
            ram = [positive(row["peak_ram_gb"], "peak RAM")
                   for row in current.values()]
            ratios = [baseline_time[seed] / seconds[seed]
                      for seed in SEEDS]
            require(len({row["timing_scope"] for row in
                         current.values()}) == 1,
                    "CPU timing scope changed across seeds")
            result.append(dict(zip(FIELDS, (
                dataset, next(iter(n)), next(iter(p)), label,
                next(iter(current.values()))["timing_scope"], thread,
                statistics.median(seconds.values()),
                statistics.median(ratios), statistics.median(ram),
                *flags))))
    require(len(result) == 42, f"Incomplete CPU settings: {dataset}")
    return result


def summary_rows(rows):
    result = []
    for method in dict.fromkeys(row["method"] for row in rows):
        for thread in THREADS:
            group = [row for row in rows if row["method"] == method and
                     row["threads"] == thread]
            valid = [row for row in group if
                     row["valid_for_cpu_selection"] == "TRUE"]
            require(len(group) == 11, "CPU scaling dataset count changed")
            result.append({
                "method": method, "threads": thread,
                "datasets": len(group), "quality_valid_datasets":
                    len(valid),
                "median_paired_speedup_all": statistics.median(
                    row["paired_speedup_vs_cpu1"] for row in group),
                "median_paired_speedup_quality_valid":
                    statistics.median(row["paired_speedup_vs_cpu1"]
                                      for row in valid) if valid else "",
            })
    require(len(result) == 42, "CPU summary method count changed")
    return result


def tex(rows):
    lines = [
        r"\begin{longtable}{lrrrl}",
        r"\caption{Mac CPU scaling across 11 datasets. Speedups are "
        r"paired by seed against the same method at one CPU thread. "
        r"The quality-valid column omits dataset settings that failed "
        r"the CPU selection gate. Full dataset-level times and flags "
        r"are supplied in the companion CSV.}"
        r"\label{tab:mac-cpu-scaling}" + "\\\\",
        r"\toprule",
        r"Method & Threads & Datasets & Valid & Median speedup "
        + "\\\\",
        r"\midrule", r"\endfirsthead", r"\toprule",
        r"Method & Threads & Datasets & Valid & Median speedup "
        + "\\\\", r"\midrule", r"\endhead",
    ]
    for row in rows:
        speed = row["median_paired_speedup_quality_valid"]
        lines.append(" & ".join((
            row["method"], str(row["threads"]),
            str(row["datasets"]), str(row["quality_valid_datasets"]),
            "NA" if speed == "" else f"{speed:.2f}")) + " \\\\")
    return "\n".join((*lines, r"\bottomrule", r"\end{longtable}")) + "\n"


def write_csv(path, rows):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: script.py QUEUE_ROOT CAMPAIGN_ROOT OUTPUT")
    queue, campaign, output = (Path(arg).resolve() for arg in sys.argv[1:])
    report = module(REPORT, "mac_panel_report")
    selector = report.selector_module()
    selector.observations(queue, campaign)
    status = {row["dataset"]: row for row in
              csv_rows(queue / "status.csv")}
    rows = []
    for dataset in selector.DATASETS:
        state = status[dataset]
        root = (campaign / "results/m3-ultra-panel-v1" /
                state["run_id"])
        audit = Path(state["audit_dir"]) if state["audit_dir"] else root
        rows.extend(dataset_rows(root, audit, dataset, report))
    require(len(rows) == 462, "Full Mac CPU scaling grid is incomplete")
    summary = summary_rows(rows)
    paths = (output.with_suffix(".csv"),
             output.with_name(output.name + "_summary.csv"),
             output.with_suffix(".tex"))
    require(not any(path.exists() for path in paths),
            "CPU scaling report already exists")
    write_csv(paths[0], rows)
    write_csv(paths[1], summary)
    paths[2].write_text(tex(summary))
    print("Saved 462 CPU settings and 42 scaling summary rows")


if __name__ == "__main__":
    main()
