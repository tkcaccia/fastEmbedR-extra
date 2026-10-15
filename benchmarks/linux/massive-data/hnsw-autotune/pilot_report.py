#!/usr/bin/env python3
"""Publish bounded pilot evidence before the scale lane finishes."""

import json
import sys
from pathlib import Path

from audit import (key, projected_seconds, read_table, recommendation,
                   valid_case_rows, write_table)


def main(root):
    cases = read_table(root / "sweep_cases.tsv", "\t")
    results = []
    failures = []
    for index, case in enumerate(cases):
        if case["scope"] != "pilot":
            continue
        path = root / "sweep" / f"case_{index:03d}.csv"
        if not path.is_file():
            failures.append({"case": str(index), "reason": "missing sweep"})
        else:
            rows = read_table(path)
            if not valid_case_rows(rows, case):
                failures.append({"case": str(index),
                                 "reason": "invalid sweep"})
            else:
                results.extend(rows)
    lookup = {key(row): row for row in results}
    chosen = []
    for dataset in ("deep", "turing"):
        for k in ("15", "30", "50"):
            best = recommendation(results, dataset, "pilot", "20000", k)
            if best is None:
                chosen.append(dict(dataset=dataset, k=k,
                                   status="no_recall_099"))
                continue
            held = lookup.get(key(best)[:-1] + ("holdout",))
            chosen.append(dict(dataset=dataset, k=k,
                status="provisional_speed_candidate", m=best["m"],
                ef_construction=best["ef_construction"],
                ef_search=best["ef_search"],
                projected_queries=best["fit_rows"],
                projected_seconds=projected_seconds(
                    best, int(best["fit_rows"])),
                tune_lower_95=best["lower_95_recall"],
                holdout_recall=held["mean_recall"] if held else "",
                holdout_lower_95=(held["lower_95_recall"]
                                  if held else ""),
                holdout_confirmed=(
                    float(held["lower_95_recall"]) >= 0.99
                    if held else False),
                query_seconds=best["query_seconds"]))
    write_table(root / "pilot_screen.csv", chosen,
        ("dataset", "k", "status", "m", "ef_construction", "ef_search",
         "tune_lower_95", "holdout_recall", "holdout_lower_95",
         "holdout_confirmed", "query_seconds", "projected_queries",
         "projected_seconds"))
    passing = [row for row in results if row["split"] == "tune" and
               float(row["lower_95_recall"]) >= 0.99]
    write_table(root / "pilot_passing.csv", passing,
                results[0].keys() if results else
                ("dataset", "scope", "k"))
    write_table(root / "pilot_failures.tsv", failures, ("case", "reason"))
    (root / "pilot_status.json").write_text(json.dumps({
        "complete": not failures, "sweep_rows": len(results),
        "failures": failures}, indent=2) + "\n")
    with (root / "stages.tsv").open("a", encoding="utf-8") as stream:
        stream.write("pilot_audit\t-\t" +
                     ("completed" if not failures else "failed") + "\n")
    print("Pilot report:", root / "pilot_screen.csv")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
