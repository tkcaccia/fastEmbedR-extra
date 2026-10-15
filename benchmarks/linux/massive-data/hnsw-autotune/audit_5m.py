#!/usr/bin/env python3
"""Audit the fresh five-million-row screen and its holdout recall."""

import csv
import json
import random
import sys
from pathlib import Path

from audit import read_table, write_table


def lower_bound(values, seed):
    rng = random.Random(seed)
    count = len(values)
    means = sorted(sum(values[rng.randrange(count)] for _ in range(count)) /
                   count for _ in range(1000))
    return means[49]


def audit(root):
    truth_cases = read_table(root / "truth_cases.tsv", "\t")
    cases = read_table(root / "sweep_cases.tsv", "\t")
    failures = []
    results = []
    expected_image = (root / "source.sha256").read_text().split()[0]
    if len(expected_image) != 64:
        failures.append(dict(case="campaign", reason="invalid image hash"))
    if len(truth_cases) != 2 or len(cases) != 3:
        failures.append(dict(case="campaign", reason="unexpected cases"))
    for case in truth_cases:
        stem = f'{case["dataset"]}_{case["scope"]}'
        for suffix in (".rds", "_geometry.csv", "_timing.csv"):
            path = root / "truth" / (stem + suffix)
            if not path.is_file() or path.stat().st_size == 0:
                failures.append(dict(case=stem, reason="missing " + suffix))
        try:
            timing, = read_table(root / "truth" / (stem + "_timing.csv"))
            if (int(timing["query_n"]) != 8192 or
                    float(timing["exact_seconds"]) <= 0):
                raise ValueError("invalid exact timing")
        except (OSError, ValueError, KeyError):
            failures.append(dict(case=stem, reason="invalid exact timing"))
    for index, case in enumerate(cases):
        name = f"case_{index:03d}"
        try:
            summary = read_table(root / "sweep" / (name + ".csv"))
            details = read_table(root / "sweep" /
                                 (name + "_queries.csv"))
            if len(summary) != 2 or len(details) != 8192:
                raise ValueError("partial sweep or query detail")
            by_split = {row["split"]: row for row in summary}
            if set(by_split) != {"tune", "holdout"}:
                raise ValueError("missing tune or holdout summary")
            for row in summary:
                if any(row[field] != str(case[field]) for field in
                       ("dataset", "scope", "shard_rows", "k", "m",
                        "ef_construction", "ef_search")):
                    raise ValueError("case identity mismatch")
                if (row["fit_rows"] != case["rows"] or
                        row["image_sha256"] != expected_image or
                        tuple(map(int, row["faissr_version"].split("."))) <
                        (0, 99, 52) or
                        int(row["n_queries"]) != 4096):
                    raise ValueError("source or query-count mismatch")
            holdout = [float(row["recall"]) for row in details
                       if row["split"] == "holdout"]
            tuning = [float(row["recall"]) for row in details
                      if row["split"] == "tune"]
            if len(holdout) != 4096 or len(tuning) != 4096:
                raise ValueError("query split mismatch")
            if len({int(row["row"]) for row in details}) != 8192:
                raise ValueError("duplicate query rows")
            observed = sum(holdout) / len(holdout)
            if abs(observed - float(by_split["holdout"]["mean_recall"])) > 1e-8:
                raise ValueError("summary and query recall disagree")
            bound = lower_bound(holdout, 1701 + index)
            row = by_split["holdout"]
            results.append(dict(case=name, dataset=case["dataset"],
                fit_rows=case["rows"], first_row=case["first_row"],
                shard_rows=case["shard_rows"], m=case["m"],
                ef_construction=case["ef_construction"],
                ef_search=case["ef_search"], holdout_mean=observed,
                holdout_bootstrap_lower95=bound,
                holdout_p10=row["p10_recall"],
                holdout_min=row["min_recall"],
                boundary_tie_rows=row["boundary_tie_rows"],
                recall_pass=bound >= 0.99,
                build_seconds=row["build_seconds"],
                query_seconds=row["query_seconds"],
                worker_elapsed_seconds=row["worker_elapsed_seconds"],
                rss_peak_bytes=row["rss_peak_bytes"],
                faissr_dll_sha256=row["faissr_dll_sha256"],
                fastembedr_dll_sha256=row["fastembedr_dll_sha256"],
                image_sha256=expected_image))
        except (OSError, KeyError, ValueError, IndexError) as error:
            failures.append(dict(case=name, reason=str(error)))
    for field in ("faissr_dll_sha256", "fastembedr_dll_sha256"):
        if len({row[field] for row in results}) > 1:
            failures.append(dict(case="campaign", reason="mixed " + field))
    write_table(root / "failures.tsv", failures, ("case", "reason"))
    fields = ("case", "dataset", "fit_rows", "first_row", "shard_rows",
              "m", "ef_construction", "ef_search", "holdout_mean",
              "holdout_bootstrap_lower95", "holdout_p10", "holdout_min",
              "boundary_tie_rows", "recall_pass", "build_seconds",
              "query_seconds", "worker_elapsed_seconds", "rss_peak_bytes",
              "faissr_dll_sha256", "fastembedr_dll_sha256",
              "image_sha256")
    write_table(root / "screen_5m.csv", results, fields)
    status = dict(complete=not failures, cases_expected=3,
                  cases_measured=len(results), recall_passes=sum(
                      row["recall_pass"] for row in results),
                  failures=failures)
    (root / "audit_5m.json").write_text(
        json.dumps(status, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(status))
    return not failures


if __name__ == "__main__":
    sys.exit(0 if audit(Path(sys.argv[1])) else 1)
