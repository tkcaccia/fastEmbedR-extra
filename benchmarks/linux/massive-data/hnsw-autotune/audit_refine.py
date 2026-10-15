#!/usr/bin/env python3
"""Audit the independent effort sweep without promoting a default."""

import json
import sys
from pathlib import Path

from audit import read_table, write_table
from audit_5m import lower_bound


EFFORT = (45, 60, 80, 120, 150, 240)


def audit(root):
    cases = read_table(root / "sweep_cases.tsv", "\t")
    truth = read_table(root / "truth_cases.tsv", "\t")
    image = (root / "source.sha256").read_text().split()[0]
    failures = []
    results = []
    if len(cases) != 3 or len(truth) != 2 or len(image) != 64:
        failures.append(dict(case="campaign", reason="invalid registry"))
    for item in truth:
        stem = f'{item["dataset"]}_refine5m'
        for suffix in (".rds", "_geometry.csv", "_timing.csv"):
            path = root / "truth" / (stem + suffix)
            if not path.is_file() or not path.stat().st_size:
                failures.append(dict(case=stem, reason="missing " + suffix))
    for index, case in enumerate(cases):
        name = f"case_{index:03d}"
        try:
            summary = read_table(root / "sweep" / (name + ".csv"))
            details = read_table(root / "sweep" /
                                 (name + "_queries.csv"))
            if len(summary) != 12 or len(details) != 8192 * 6:
                raise ValueError("partial effort sweep")
            grouped = {(int(row["ef_search"]), row["split"]): row
                       for row in summary}
            expected = {(ef, split) for ef in EFFORT
                        for split in ("tune", "holdout")}
            if set(grouped) != expected:
                raise ValueError("missing or duplicate effort/split")
            for ef in EFFORT:
                relevant = [row for row in details
                            if int(row["ef_search"]) == ef]
                if len(relevant) != 8192 or len({int(row["row"])
                        for row in relevant}) != 8192:
                    raise ValueError("query rows are incomplete")
                for split in ("tune", "holdout"):
                    row = grouped[ef, split]
                    if (row["dataset"] != case["dataset"] or
                        row["scope"] != "refine5m" or
                        row["fit_rows"] != case["rows"] or
                        row["m"] != case["m"] or
                        row["ef_construction"] !=
                            case["ef_construction"] or
                        row["image_sha256"] != image or
                        tuple(map(int, row["faissr_version"].split("."))) <
                            (0, 99, 52)):
                        raise ValueError("source or case identity changed")
                    values = [float(item["recall"]) for item in relevant
                              if item["split"] == split]
                    if len(values) != 4096:
                        raise ValueError("query split is incomplete")
                    mean = sum(values) / len(values)
                    if abs(mean - float(row["mean_recall"])) > 1e-8:
                        raise ValueError("query and summary recall differ")
                    lower = lower_bound(values, 2200 + index * 20 + ef +
                                        (1 if split == "holdout" else 0))
                    miss_fraction = sum(v < 0.99 for v in values) / 4096
                    results.append(dict(case=name, dataset=case["dataset"],
                        first_row=case["first_row"], fit_rows=case["rows"],
                        m=case["m"], ef_construction=case["ef_construction"],
                        ef_search=ef, split=split, mean_recall=mean,
                        bootstrap_lower95=lower,
                        fraction_queries_below_099=miss_fraction,
                        recall_gate=lower >= 0.99,
                        consistency_gate=miss_fraction <= 0.01,
                        build_seconds=row["build_seconds"],
                        query_seconds=row["query_seconds"],
                        rss_peak_bytes=row["rss_peak_bytes"],
                        hostname=row["hostname"],
                        faissr_dll_sha256=row["faissr_dll_sha256"],
                        fastembedr_dll_sha256=row["fastembedr_dll_sha256"],
                        image_sha256=image))
        except (OSError, KeyError, ValueError, IndexError) as error:
            failures.append(dict(case=name, reason=str(error)))
    fields = ("case", "dataset", "first_row", "fit_rows", "m",
              "ef_construction", "ef_search", "split", "mean_recall",
              "bootstrap_lower95", "fraction_queries_below_099",
              "recall_gate", "consistency_gate", "build_seconds",
              "query_seconds", "rss_peak_bytes", "hostname",
              "faissr_dll_sha256", "fastembedr_dll_sha256", "image_sha256")
    write_table(root / "refine_5m.csv", results, fields)
    write_table(root / "failures.tsv", failures, ("case", "reason"))
    status = dict(complete=not failures, cases_expected=3,
                  cases_measured=len(results) // 12,
                  gated_holdout=sum(row["recall_gate"] and
                      row["consistency_gate"] for row in results
                      if row["split"] == "holdout"), failures=failures)
    (root / "audit_refine.json").write_text(
        json.dumps(status, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(status))
    return not failures


if __name__ == "__main__":
    sys.exit(0 if audit(Path(sys.argv[1])) else 1)
