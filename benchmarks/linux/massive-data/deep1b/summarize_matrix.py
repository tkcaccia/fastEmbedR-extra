#!/usr/bin/env python3
"""Make compact method and job ledgers without loading embedding payloads."""

import argparse
import csv
import json
from pathlib import Path


METHODS = ("pca", "knn", "tsne", "umap", "leiden", "louvain")
FIELDS = ("mode", "rows", "lane", "job", "method", "status",
          "audit_status", "seconds", "stage_rss_bytes",
          "job_rss_peak_bytes", "gpu_peak_per_device_json",
          "ssd_peak_allocated_bytes", "output_bytes", "plot",
          "knn_recall_mean", "knn_recall_min", "error", "campaign")


def csv_rows(path, delimiter=","):
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream, delimiter=delimiter))


def first_row(path):
    rows = csv_rows(path)
    return rows[0] if rows else {}


def job_rss(path):
    if not path.is_file():
        return ""
    for line in path.read_text(errors="replace").splitlines():
        if "Maximum resident set size (kbytes):" in line:
            return str(int(line.split(":", 1)[1].strip()) * 1024)
    return ""


def status_for(method, case, root, unsupported):
    if method in unsupported:
        return "unsupported", unsupported[method]
    if method == "knn":
        record = first_row(root / "knn.csv")
        return ("ok" if record else "missing", "")
    metrics = first_row(case / "metrics.csv")
    if metrics.get("status") != "ok":
        error_path = case / "fit.error.txt"
        reason = metrics.get("error", "")
        if error_path.is_file():
            reason = error_path.read_text().strip()
        return ("failed" if reason else "missing", reason)
    return "ok", ""


def summarize_case(job, root):
    mode = job["mode"]
    backend = "cuda" if job["lane"].startswith("cuda") else "cpu"
    suffix = "classic" if mode == "classic" else "fullgraph"
    stages = {row["stage"]: row for row in csv_rows(root / "stages.csv")}
    unsupported = {row["method"]: row["reason"] for row in
                   csv_rows(root / "unsupported_methods.tsv", "\t")}
    memory = first_row(root / "gpu_memory.csv")
    disk = first_row(root / "disk_peak.csv")
    knn = first_row(root / "knn.csv")
    audit = {}
    if (root / "audit.json").is_file():
        audit = json.loads((root / "audit.json").read_text())
    methods = ("pca", "tsne", "umap") if mode == "classic" else METHODS
    records = []
    for method in methods:
        name = f"{backend}_{method}_{job['rows']}_{suffix}"
        case = root / "results" / name
        status, reason = status_for(method, case, root, unsupported)
        plot = root / "figures" / (name + ".png")
        output = case / "output.f32"
        if method in ("leiden", "louvain"):
            output = root / "work" / (method + "_labels.u32")
        if status == "ok" and method != "knn":
            expected = int(job["rows"]) * (4 if method in
                ("leiden", "louvain") else 8)
            if (not output.is_file() or output.stat().st_size != expected
                    or not plot.is_file()):
                status, reason = "incomplete", "output or all-row PNG missing"
        stage = stages.get(method, {})
        records.append(dict(mode=mode, rows=job["rows"],
                            lane=job["lane"], job=job["job"],
                            method=method, status=status,
                            audit_status=audit.get("status", "missing"),
                            seconds=stage.get("seconds", ""),
                            stage_rss_bytes=stage.get("peak_rss_bytes", ""),
                            job_rss_peak_bytes=job_rss(root / "time.txt"),
                            gpu_peak_per_device_json=memory.get(
                                "peak_per_device_json", ""),
                            ssd_peak_allocated_bytes=disk.get(
                                "peak_allocated_bytes", ""),
                            output_bytes=output.stat().st_size
                            if output.is_file() else "",
                            plot=str(plot) if plot.is_file() else "",
                            knn_recall_mean=knn.get("observed_recall", "")
                            if method == "knn" else "",
                            knn_recall_min=knn.get("minimum_row_recall", "")
                            if method == "knn" else "",
                            error=reason, campaign=str(root)))
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ledger", type=Path,
                        help="Deep1B matrix jobs.tsv")
    parser.add_argument("--output", type=Path,
                        help="CSV output (default: beside jobs.tsv)")
    args = parser.parse_args()
    jobs = csv_rows(args.ledger, "\t")
    if not jobs:
        raise SystemExit("Matrix ledger has no jobs")
    output = args.output or args.ledger.with_name("methods.csv")
    records = []
    for job in jobs:
        records.extend(summarize_case(job, Path(job["campaign"])))
    with output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, FIELDS)
        writer.writeheader()
        writer.writerows(records)
    print(f"Wrote {len(records)} method outcomes to {output}")


if __name__ == "__main__":
    main()
