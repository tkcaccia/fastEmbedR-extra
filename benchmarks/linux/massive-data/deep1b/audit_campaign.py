#!/usr/bin/env python3
"""Audit every submitted case in a Deep1B/Turing campaign."""

import argparse
import csv
import gzip
import json
import math
from pathlib import Path


def read_first_row(path, delimiter=","):
    with path.open(newline="") as handle:
        return next(csv.DictReader(handle, delimiter=delimiter))


def finite_number(value):
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def audit_case(campaign, case, warnings, first_row=1,
               exact_graph=False):
    name = case["case"]
    path = campaign / "results" / name
    failures = []
    try:
        status = read_first_row(path / "status.tsv", "\t")
        metrics = read_first_row(path / "metrics.csv")
    except (FileNotFoundError, StopIteration, csv.Error) as exc:
        return [f"{name}: missing or invalid result: {exc}"]
    if status.get("exit_code") != "0" or metrics.get("status") != "ok":
        failures.append(
            f"{name}: exit={status.get('exit_code')} "
            f"status={metrics.get('status')} error={metrics.get('error')}"
        )
    for key, expected in (
        ("backend_observed", case["backend"]),
        ("backend_requested", case["backend"]),
        ("mode", case["mode"]),
    ):
        if metrics.get(key) != expected:
            failures.append(f"{name}: {key}={metrics.get(key)!r}, expected {expected}")
    if not finite_number(metrics.get("rows")) or (
        float(metrics["rows"]) != float(case["rows"])
    ):
        failures.append(f"{name}: fitted row count mismatch")
    if metrics.get("first_row") != str(first_row):
        failures.append(f"{name}: input row offset mismatch")
    if metrics.get("finite_sample") != "TRUE":
        failures.append(f"{name}: finite output sample not confirmed")
    if case["backend"] == "cuda":
        try:
            gpu = read_first_row(path / "gpu_memory.csv")
            if (gpu.get("status") != "ok" or
                not finite_number(gpu.get("peak_bytes")) or
                float(gpu["peak_bytes"]) <= 0 or
                int(gpu["matched_samples"]) <= 0):
                raise ValueError("no observed GPU process memory")
            requested = case.get("devices", "-")
            if requested and requested != "-" and (
                int(gpu.get("device_count", "0")) <
                len(requested.split(","))
            ):
                raise ValueError("not all requested GPUs were observed")
        except (OSError, KeyError, ValueError, StopIteration, csv.Error) as exc:
            failures.append(f"{name}: GPU memory evidence: {exc}")
    for key in ("elapsed_seconds", "rss_peak_bytes", "output_bytes"):
        if not finite_number(metrics.get(key)) or float(metrics[key]) <= 0:
            failures.append(f"{name}: invalid {key}")
    if case["mode"] in ("knn", "umap", "tsne", "cluster"):
        if metrics.get("knn_backend") != case["backend"]:
            failures.append(f"{name}: KNN backend mismatch")
    if case["mode"] == "knn":
        recall = metrics.get("knn_recall_mean")
        if not finite_number(recall):
            failures.append(f"{name}: observed KNN recall missing")
        elif float(recall) < 0.99:
            failures.append(f"{name}: sampled KNN recall {recall} < 0.99")
        try:
            with gzip.open(path / "knn_audit_rows.csv.gz", "rt") as handle:
                sampled = list(csv.DictReader(handle))
            expected = int(metrics["knn_audit_rows"])
            if (expected < 1 or len(sampled) != expected or
                len({int(row["row"]) for row in sampled}) != expected or
                any(not 0 <= float(row["recall"]) <= 1
                    for row in sampled)):
                raise ValueError("exact-query row ledger is incomplete")
            observed = sum(float(row["recall"]) for row in sampled) / expected
            if abs(observed - float(recall)) > 1e-8:
                raise ValueError("row recalls disagree with metrics.csv")
            if case.get("phase") == "graph10m" and expected < 1024:
                raise ValueError("independent graph audit needs 1024 rows")
        except (OSError, KeyError, ValueError, csv.Error) as exc:
            failures.append(f"{name}: exact KNN row evidence: {exc}")
        if case["backend"] == "cpu":
            try:
                shard_count = int(metrics["hnsw_shard_count"])
                with gzip.open(path / "hnsw_shards.csv.gz", "rt") as handle:
                    shards = list(csv.DictReader(handle))
                if (shard_count < 1 or len(shards) != shard_count or
                    [int(row["shard"]) for row in shards] !=
                        list(range(1, shard_count + 1)) or
                    sum(int(row["reference_rows"]) for row in shards) !=
                        int(case["rows"])):
                    raise ValueError("shard ledger does not cover all rows")
                for field, key in (("m", "hnsw_m_effective"),
                                   ("ef_construction",
                                    "hnsw_ef_construction_effective"),
                                   ("ef_search", "hnsw_ef_search_effective")):
                    values = sorted({int(row[field]) for row in shards})
                    if min(values) < 1 or metrics.get(key) != ",".join(
                            str(value) for value in values):
                        raise ValueError(f"{key} disagrees with shard ledger")
                rules = sorted({row["tuning_rule"] for row in shards})
                if (not all(rules) or metrics.get("hnsw_tuning_rule_effective")
                        != ",".join(rules)):
                    raise ValueError("effective tuning rule is missing")
            except (OSError, KeyError, ValueError, csv.Error) as exc:
                failures.append(f"{name}: effective HNSW evidence: {exc}")
        if exact_graph:
            try:
                with (path / "knn_exact_quality.csv").open(
                        newline="") as handle:
                    exact = list(csv.DictReader(handle))
                holdout, = [row for row in exact
                            if row.get("split") == "holdout"]
                if (len(exact) != 2 or
                    holdout.get("query_count") != "4096" or
                    float(holdout["lower95_recall"]) < 0.99 or
                    float(holdout["fraction_below_099"]) > 0.01):
                    raise ValueError("independent recall gate missed")
            except (OSError, KeyError, ValueError, csv.Error) as exc:
                failures.append(f"{name}: exact KNN quality: {exc}")
    elif case["mode"] == "cluster":
        try:
            quality = read_first_row(path / "quality.csv")
            if (float(quality["scanned_rows"]) != float(case["rows"]) or
                float(quality["input_first_row"]) != first_row or
                int(quality["landmarks_checked"]) < 1 or
                int(quality["landmark_label_mismatches"]) != 0 or
                float(quality["communities"]) < 1 or
                not 0 <= float(quality["min_confidence"]) <= 1 or
                not 0 <= float(quality["max_confidence"]) <= 1):
                raise ValueError("full clustering scan did not pass")
            with gzip.open(path / "cluster_sample.csv.gz", "rt") as handle:
                sample = list(csv.DictReader(handle))
            if len(sample) != 512 or any(
                int(row["row_id"]) < first_row or
                int(row["row_id"]) >= first_row + int(case["rows"]) or
                int(row["membership"]) < 1 or
                not 0 <= float(row["confidence"]) <= 1
                for row in sample
            ):
                raise ValueError("invalid clustering sample")
        except (OSError, KeyError, ValueError, StopIteration, csv.Error) as exc:
            failures.append(f"{name}: invalid clustering quality: {exc}")
        if metrics.get("cluster_method") != case.get("cluster_method"):
            failures.append(f"{name}: clustering method mismatch")
    else:
        try:
            quality = read_first_row(path / "quality.csv")
        except (FileNotFoundError, StopIteration, csv.Error) as exc:
            failures.append(f"{name}: missing or invalid quality: {exc}")
        else:
            for key in ("trustworthiness", "knn_preservation_30"):
                if not finite_number(quality.get(key)):
                    failures.append(f"{name}: invalid quality {key}")
            if quality.get("input_first_row") != str(first_row):
                failures.append(f"{name}: quality row offset mismatch")
        try:
            with gzip.open(path / "plot_sample.csv.gz", "rt") as handle:
                plot_rows = list(csv.DictReader(handle))
            if len(plot_rows) != min(4096, int(case["rows"])):
                raise ValueError("expected 4096 quality rows")
            if int(plot_rows[0]["row_id"]) < first_row:
                raise ValueError("plot sample row offset mismatch")
        except (OSError, ValueError, KeyError, csv.Error) as exc:
            failures.append(f"{name}: invalid plot sample: {exc}")
        try:
            with gzip.open(path / "plot_sample_10000.csv.gz", "rt") as handle:
                visual_rows = list(csv.DictReader(handle))
            expected = min(10000, int(case["rows"]))
            dimensions = [f"dim{i}" for i in range(1,
                          int(case.get("components", "2")) + 1)]
            ids = [int(row["row_id"]) for row in visual_rows]
            if (len(ids) != expected or len(set(ids)) != expected or
                ids[0] < first_row or
                ids[-1] >= first_row + int(case["rows"]) or
                any(not finite_number(row.get(key))
                    for row in visual_rows for key in dimensions)):
                raise ValueError("invalid visual sample rows or coordinates")
        except (OSError, ValueError, KeyError, IndexError, csv.Error) as exc:
            failures.append(f"{name}: invalid visual sample: {exc}")
    source_check = path / "source_check.txt"
    if not source_check.is_file() or not source_check.read_text().strip():
        failures.append(f"{name}: source checksum evidence missing")
    return failures


def audit(campaign):
    failures = []
    warnings = []
    cases = []
    first_row = 1
    launch = {}
    try:
        jobs = read_first_row(campaign / "jobs.tsv", "\t")
        if not jobs.get("job_id"):
            failures.append("Campaign has no submitted job IDs")
    except (FileNotFoundError, StopIteration, csv.Error):
        failures.append("Campaign jobs.tsv is missing or empty")
    for path in sorted(campaign.glob("cases_*.tsv")):
        with path.open(newline="") as handle:
            cases.extend(csv.DictReader(handle, delimiter="\t"))
    try:
        launch = dict(line.strip().split("=", 1) for line in
                      (campaign / "launch.txt").read_text().splitlines())
        first_row = int(launch.get("first_row", "1"))
        with (campaign / "registry.tsv").open(newline="") as handle:
            registry = list(csv.DictReader(handle, delimiter="\t"))
        expected = [row for row in registry if
                    row["phase"] == launch["phase"] and
                    (launch["lane"] == "all" or
                     row["backend"] == launch["lane"])]
        if launch.get("case_filter"):
            expected = [row for row in expected if
                        row["case"] == launch["case_filter"]]
        if {row["case"] for row in expected} != {
            row["case"] for row in cases
        }:
            failures.append("Submitted case registry is incomplete")
    except (FileNotFoundError, KeyError, ValueError, csv.Error) as exc:
        failures.append(f"Campaign launch registry is invalid: {exc}")
    if not cases:
        failures.append("Campaign has no case registry")
    for case in cases:
        failures.extend(audit_case(campaign, case, warnings,
                                   first_row,
                                   launch.get("phase") ==
                                   "fresh5m_graph"))
        if (launch.get("phase") in ("fresh5m", "fresh5m_3d",
                                    "scale10m", "boundary", "billion") and
            case["mode"] in ("pca", "umap", "tsne")):
            path = campaign / "results" / case["case"]
            suffix = (".png" if case.get("components") == "2" else
                      "_xy.png")
            if not (path / "figures" / f"{case['case']}{suffix}").is_file():
                failures.append(f"{case['case']}: full-row PNG missing")
        if (launch.get("phase") == "billion" and
            launch.get("prune_billion") == "1" and
            not (campaign / "results" / case["case"] /
                 "pruned_payloads.tsv").is_file()):
                failures.append(f"{case['case']}: payload ledger missing")
    return {
        "campaign": str(campaign),
        "status": "PASS" if not failures else "FAIL",
        "case_count": len(cases),
        "failures": failures,
        "warnings": warnings,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = audit(args.campaign.resolve())
    output = args.output or args.campaign / "audit.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"{report['status']}: {report['case_count']} cases; "
          f"{len(report['failures'])} failures; "
          f"{len(report['warnings'])} recall warnings")
    for message in report["failures"] + report["warnings"]:
        print(message)
    raise SystemExit(0 if report["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
