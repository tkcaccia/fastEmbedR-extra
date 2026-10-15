#!/usr/bin/env python3
"""Audit exact sampled-query recall on larger unseen reference windows."""

import json
import statistics
import sys
from pathlib import Path

from audit import read_table, write_table
from audit_5m import lower_bound


def audit(root):
    cases = read_table(root / "sweep_cases.tsv", "\t")
    expected_hash = (root / "source.sha256").read_text().split()[0]
    failures, results = [], []
    for index, case in enumerate(cases):
        name = f"case_{index:03d}"
        stem = f'{case["dataset"]}_{case["scope"]}'
        try:
            if not (root / "truth" / (stem + ".rds")).is_file():
                raise ValueError("Missing exact reference")
            summary = read_table(root / "sweep" / (name + ".csv"))
            details = read_table(root / "sweep" /
                                 (name + "_queries.csv"))
            count = int(case["query_count"])
            if len(summary) != 2 or len(details) != count or len(
                    {int(row["row"]) for row in details}) != count:
                raise ValueError("Incomplete or duplicate queries")
            for split in ("tune", "holdout"):
                row, = [item for item in summary
                        if item["split"] == split]
                if (row["image_sha256"] != expected_hash or
                    row["fit_rows"] != case["rows"] or
                    any(row[key] != case[key] for key in
                        ("dataset", "scope", "m", "ef_construction",
                         "ef_search", "shard_rows"))):
                    raise ValueError("Source or parameter identity changed")
                recalls = [float(item["recall"]) for item in details
                           if item["split"] == split]
                if len(recalls) != count // 2 or abs(
                        statistics.mean(recalls) -
                        float(row["mean_recall"])) > 1e-8:
                    raise ValueError("Per-query recall mismatch")
                results.append(dict(dataset=case["dataset"],
                    scope=case["scope"], rows=case["rows"],
                    first_row=case["first_row"], split=split,
                    query_count=len(recalls), m=case["m"],
                    ef_construction=case["ef_construction"],
                    ef_search=case["ef_search"],
                    mean_recall=statistics.mean(recalls),
                    lower95=lower_bound(recalls, 4200 + index * 2 +
                                        (split == "holdout")),
                    fraction_below_099=sum(x < 0.99 for x in recalls) /
                        len(recalls),
                    build_seconds=row["build_seconds"],
                    query_seconds=row["query_seconds"],
                    rss_peak_bytes=row["rss_peak_bytes"],
                    image_sha256=expected_hash))
        except (OSError, KeyError, ValueError) as exc:
            failures.append(f"{name}: {exc}")
    fields = ("dataset", "scope", "rows", "first_row", "split",
              "query_count", "m", "ef_construction", "ef_search",
              "mean_recall", "lower95", "fraction_below_099",
              "build_seconds", "query_seconds", "rss_peak_bytes",
              "image_sha256")
    write_table(root / "large_recall.csv", results, fields)
    status = dict(complete=not failures, failures=failures,
                  recall_gaps=[f'{row["dataset"]}/{row["scope"]}'
                    for row in results if row["split"] == "holdout" and
                    (row["lower95"] < 0.99 or
                     row["fraction_below_099"] > 0.01)],
                  note="1B uses 128 holdout queries; exploratory, not "
                       "a publication-quality recall guarantee")
    (root / "audit_large_probe.json").write_text(
        json.dumps(status, indent=2) + "\n")
    print(json.dumps(status))
    return not failures


if __name__ == "__main__":
    sys.exit(0 if audit(Path(sys.argv[1])) else 1)
