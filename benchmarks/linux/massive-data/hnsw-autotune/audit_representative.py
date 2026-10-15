#!/usr/bin/env python3
"""Select the fastest setting that passes every separated holdout."""

import csv
import json
import statistics
import sys
from pathlib import Path

from audit import read_table, write_table
from audit_5m import lower_bound


def audit(root):
    truth = read_table(root / "truth_cases.tsv", "\t")
    cases = read_table(root / "sweep_cases.tsv", "\t")
    image = (root / "source.sha256").read_text().split()[0]
    failures, rows = [], []
    if len(truth) != 6 or len(cases) != 30 or len(image) != 64:
        failures.append("Incomplete registry or image identity")
    for item in truth:
        stem = f'{item["dataset"]}_{item["scope"]}'
        for suffix in (".rds", "_timing.csv"):
            if not (root / "truth" / (stem + suffix)).is_file():
                failures.append(f"Missing exact truth: {stem}{suffix}")
    for index, case in enumerate(cases):
        name = f"case_{index:03d}"
        try:
            summary = read_table(root / "sweep" / (name + ".csv"))
            detail = read_table(root / "sweep" /
                                (name + "_queries.csv"))
            if len(summary) != 2 or len(detail) != 2048:
                raise ValueError("Incomplete tune/holdout results")
            if len({int(row["row"]) for row in detail}) != 2048:
                raise ValueError("Duplicate query rows")
            for split in ("tune", "holdout"):
                record, = [row for row in summary
                           if row["split"] == split]
                if any(record[key] != str(case[key]) for key in
                       ("dataset", "scope", "shard_rows", "m",
                        "ef_construction", "ef_search")):
                    raise ValueError("Case identity mismatch")
                if record["fit_rows"] != case["rows"]:
                    raise ValueError("Fit row count mismatch")
                if record["image_sha256"] != image or int(
                        record["n_queries"]) != 1024:
                    raise ValueError("Image or query identity mismatch")
                recall = [float(row["recall"]) for row in detail
                          if row["split"] == split]
                if len(recall) != 1024 or abs(statistics.mean(recall) -
                        float(record["mean_recall"])) > 1e-8:
                    raise ValueError("Per-query recall disagrees with CSV")
                bound = lower_bound(recall, 3100 + index * 2 +
                                    (split == "holdout"))
                rows.append(dict(dataset=case["dataset"],
                    scope=case["scope"], first_row=case["first_row"],
                    split=split, shard_rows=case["shard_rows"], m=case["m"],
                    ef_construction=case["ef_construction"],
                    ef_search=case["ef_search"],
                    mean_recall=statistics.mean(recall),
                    lower95=bound,
                    fraction_below_099=sum(x < 0.99 for x in recall) /
                        len(recall),
                    build_seconds=record["build_seconds"],
                    query_seconds=record["query_seconds"],
                    rss_peak_bytes=record["rss_peak_bytes"],
                    cpu_model=record["cpu_model"],
                    image_sha256=image))
        except (OSError, KeyError, ValueError, csv.Error) as exc:
            failures.append(f"{name}: {exc}")
    fields = ("dataset", "scope", "first_row", "split", "shard_rows", "m",
              "ef_construction", "ef_search", "mean_recall", "lower95",
              "fraction_below_099", "build_seconds", "query_seconds",
              "rss_peak_bytes", "cpu_model", "image_sha256")
    write_table(root / "representative_results.csv", rows, fields)
    selected = []
    for dataset in ("deep", "turing"):
        for shard_rows in ("50000", "250000"):
            group = [row for row in rows if row["dataset"] == dataset and
                     row["shard_rows"] == shard_rows]
            for scope in ("rep_early", "rep_middle", "rep_late"):
                if len({row["cpu_model"] for row in group if
                        row["scope"] == scope}) > 1:
                    failures.append(f"Mixed CPU models: {dataset}/"
                                    f"{shard_rows}/{scope}")
            candidates = []
            keys = sorted({(row["m"], row["ef_construction"],
                           row["ef_search"]) for row in group})
            for key in keys:
                subset = [row for row in group if
                    (row["m"], row["ef_construction"],
                     row["ef_search"]) == key]
                if (len(subset) != 6 or
                    len({row["scope"] for row in subset}) != 3 or
                    any(row["lower95"] < 0.99 for row in subset)):
                    continue
                costs = {row["scope"]: float(row["build_seconds"]) +
                    float(row["query_seconds"]) * 5_000_000 / 2048
                    for row in subset if row["split"] == "holdout"}
                candidates.append((key, costs))
            if candidates:
                minima = {scope: min(costs[scope] for _, costs in candidates)
                          for scope in ("rep_early", "rep_middle",
                                        "rep_late")}
                ranked = []
                for key, costs in candidates:
                    relative = statistics.median(
                        costs[scope] / minima[scope] for scope in minima)
                    ranked.append((relative, statistics.median(
                        costs.values()), key))
                relative, cost, key = min(ranked)
                selected.append(dict(dataset=dataset,
                    shard_rows=shard_rows, m=key[0],
                    ef_construction=key[1], ef_search=key[2],
                    relative_cost=relative,
                    projected_5m_seconds=cost, image_sha256=image))
    write_table(root / "selected.csv", selected,
                ("dataset", "shard_rows", "m", "ef_construction",
                 "ef_search",
                 "relative_cost", "projected_5m_seconds", "image_sha256"))
    result = dict(complete=not failures, failures=failures,
                  selected_datasets=sorted({row["dataset"]
                                            for row in selected}),
                  query_scope="three_disjoint_5m_windows")
    (root / "audit_representative.json").write_text(
        json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    return not failures


if __name__ == "__main__":
    sys.exit(0 if audit(Path(sys.argv[1])) else 1)
