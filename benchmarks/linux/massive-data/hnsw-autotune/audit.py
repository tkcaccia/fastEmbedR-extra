#!/usr/bin/env python3
"""Audit completeness and pilot-to-scale transfer without hiding misses."""

import csv
import json
import sys
from pathlib import Path


def read_table(path, delimiter=","):
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream, delimiter=delimiter))


def write_table(path, rows, fields):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fields, delimiter="\t" if
                                path.suffix == ".tsv" else ",")
        writer.writeheader()
        writer.writerows(rows)


def key(row):
    return tuple(row[field] for field in ("dataset", "scope", "shard_rows",
                                          "k", "m", "ef_construction",
                                          "ef_search", "split"))


def valid_case_rows(rows, case):
    required = {"dataset", "scope", "fit_rows", "shard_rows", "k",
                "m", "ef_construction", "ef_search", "split",
                "mean_recall", "lower_95_recall", "query_seconds",
                "build_seconds", "collect_seconds", "merge_seconds",
                "timing_median_seconds", "timing_queries",
                "rss_peak_bytes", "n_queries", "hostname",
                "worker_elapsed_seconds",
                "faissr_m", "faissr_ef_construction",
                "faissr_ef_search", "faissr_rule",
                "faissr_dll_sha256", "fastembedr_dll_sha256",
                "faissr_version", "fastembedr_version", "image_sha256"}
    if len(rows) != 46 or not required.issubset(rows[0]):
        return False
    expected = {(str(k), str(ef), split)
                for k in (15, 30, 50)
                for ef in (45, 60, 80, 120, 150, 240, 480, 960)
                if ef >= k + 1 for split in ("tune", "holdout")}
    if {(r["k"], r["ef_search"], r["split"]) for r in rows} != expected:
        return False
    if len({r["worker_elapsed_seconds"] for r in rows}) != 1:
        return False
    try:
        return all(
            r["dataset"] == case["dataset"] and
            r["scope"] == case["scope"] and
            r["fit_rows"] == case["rows"] and
            r["shard_rows"] == case["shard_rows"] and
            r["m"] == case["m"] and
            r["ef_construction"] == case["ef_construction"] and
            0 <= float(r["mean_recall"]) <= 1 and
            0 <= float(r["lower_95_recall"]) <=
            float(r["mean_recall"]) and
            int(r["n_queries"]) == 1024 and
            0 <= float(r["query_seconds"]) < float("inf") and
            0 <= float(r["build_seconds"]) < float("inf") and
            0 <= float(r["collect_seconds"]) < float("inf") and
            0 <= float(r["merge_seconds"]) < float("inf") and
            0 < float(r["timing_median_seconds"]) < float("inf") and
            int(r["timing_queries"]) > 0 and
            0 < float(r["worker_elapsed_seconds"]) < float("inf") and
            float(r["rss_peak_bytes"]) > 0
            for r in rows)
    except (KeyError, TypeError, ValueError):
        return False


def recommendation(rows, dataset, scope, shard_rows, k):
    choices = [r for r in rows if r["dataset"] == dataset and
               r["scope"] == scope and r["shard_rows"] == shard_rows and
               r["k"] == k and r["split"] == "tune"]
    passing = [r for r in choices if
               float(r["lower_95_recall"]) >= 0.99]
    if not passing:
        return None
    return min(passing, key=lambda r: (
        projected_seconds(r, int(r["fit_rows"])),
        int(r["m"]), int(r["ef_construction"]),
        int(r["ef_search"])))


def projected_seconds(row, queries):
    measured_queries = 2 * int(row["n_queries"])
    search = (float(row["timing_median_seconds"]) /
              int(row["timing_queries"]))
    other = (float(row["collect_seconds"]) +
             float(row["merge_seconds"])) / measured_queries
    return float(row["build_seconds"]) + queries * (search + other)


def main(root):
    truth = read_table(root / "truth_cases.tsv", "\t")
    cases = read_table(root / "sweep_cases.tsv", "\t")
    failures = []
    results = []
    truth_cost = {}
    sweep_cost = {}
    for case in truth:
        path = root / "truth" / f'{case["dataset"]}_{case["scope"]}.rds'
        if not path.is_file():
            failures.append({"case": path.name, "reason": "missing truth"})
        geometry = path.with_name(path.stem + "_geometry.csv")
        if not geometry.is_file():
            failures.append({"case": geometry.name,
                             "reason": "missing geometry"})
        timing = path.with_name(path.stem + "_timing.csv")
        try:
            record, = read_table(timing)
            if (record["dataset"] != case["dataset"] or
                    record["scope"] != case["scope"] or
                    int(record["query_n"]) != 2048 or
                    float(record["exact_seconds"]) <= 0 or
                    float(record["worker_elapsed_seconds"]) <= 0):
                raise ValueError("invalid truth timing")
            truth_cost[case["dataset"], case["scope"]] = record
        except (OSError, ValueError, KeyError):
            failures.append({"case": timing.name,
                             "reason": "missing or invalid truth timing"})
    for index, case in enumerate(cases):
        path = root / "sweep" / f"case_{index:03d}.csv"
        if not path.is_file():
            failures.append({"case": str(index), "reason": "missing sweep"})
            continue
        query_path = root / "sweep" / f"case_{index:03d}_queries.csv"
        detail_count = -1
        if query_path.is_file():
            with query_path.open(encoding="utf-8") as stream:
                detail_count = sum(1 for _ in stream) - 1
        if detail_count != 16384:
            failures.append({"case": str(index),
                             "reason": "missing or partial query detail"})
        try:
            rows = read_table(path)
        except (OSError, csv.Error, UnicodeError) as error:
            failures.append({"case": str(index),
                             "reason": f"unreadable sweep: {error}"})
            continue
        if not valid_case_rows(rows, case):
            failures.append({"case": str(index), "reason": "invalid sweep"})
            continue
        results.extend(rows)
        sweep_cost[index] = float(rows[0]["worker_elapsed_seconds"])
    cost_rows = []
    for dataset in ("deep", "turing"):
        for scope in ("pilot", "scale"):
            indices = [i for i, case in enumerate(cases) if
                       case["dataset"] == dataset and case["scope"] == scope]
            exact = truth_cost.get((dataset, scope), {})
            sweep_seconds = sum(sweep_cost[i] for i in indices if
                                i in sweep_cost)
            truth_seconds = float(exact["worker_elapsed_seconds"]) if (
                exact) else 0
            cost_rows.append(dict(dataset=dataset, scope=scope,
                status="complete" if exact and all(
                    i in sweep_cost for i in indices) else "partial",
                exact_reference_seconds=exact.get("exact_seconds", ""),
                truth_worker_seconds=truth_seconds if exact else "",
                sweep_cases_expected=len(indices),
                sweep_cases_measured=sum(i in sweep_cost for i in indices),
                sum_sweep_worker_seconds=sweep_seconds,
                sum_experiment_worker_seconds=truth_seconds + sweep_seconds))
    write_table(root / "experiment_cost.csv", cost_rows,
        ("dataset", "scope", "status", "exact_reference_seconds",
         "truth_worker_seconds", "sweep_cases_expected",
         "sweep_cases_measured", "sum_sweep_worker_seconds",
         "sum_experiment_worker_seconds"))
    if len({key(r) for r in results}) != len(results):
        failures.append({"case": "all", "reason": "duplicate result keys"})
    for field in ("image_sha256", "faissr_dll_sha256",
                  "fastembedr_dll_sha256",
                  "faissr_version", "fastembedr_version"):
        if (not results or "" in {r[field] for r in results} or
                len({r[field] for r in results}) > 1):
            failures.append({"case": "all",
                             "reason": f"mixed package identity: {field}"})
    write_table(root / "failures.tsv", failures, ("case", "reason"))
    if results:
        write_table(root / "sweep_summary.csv", results, results[0].keys())
    lookup = {key(r): r for r in results}
    selected = []
    for dataset in ("deep", "turing"):
        for scope in ("pilot", "scale"):
            for shard in ("20000", "50000", "1000000"):
                if scope == "pilot" and shard != "20000":
                    continue
                for k in ("15", "30", "50"):
                    best = recommendation(results, dataset, scope, shard, k)
                    if best is None:
                        selected.append(dict(dataset=dataset, scope=scope,
                            shard_rows=shard, k=k, status="no_recall_099"))
                        continue
                    holdout = lookup.get(key(best)[:-1] + ("holdout",))
                    selected.append(dict(dataset=dataset, scope=scope,
                        shard_rows=shard, k=k,
                        status="provisional_speed_candidate",
                        m=best["m"], ef_construction=best["ef_construction"],
                        ef_search=best["ef_search"],
                        projected_queries=best["fit_rows"],
                        projected_seconds=projected_seconds(
                            best, int(best["fit_rows"])),
                        tune_recall=best["mean_recall"],
                        tune_lower_95=best["lower_95_recall"],
                        holdout_recall=(holdout["mean_recall"]
                                        if holdout else ""),
                        holdout_lower_95=(holdout["lower_95_recall"]
                                          if holdout else ""),
                        holdout_confirmed=(
                            float(holdout["lower_95_recall"]) >= 0.99
                            if holdout else False),
                        query_seconds=best["query_seconds"],
                        build_seconds=best["build_seconds"]))
    fields = ("dataset", "scope", "shard_rows", "k", "status", "m",
              "ef_construction", "ef_search", "tune_recall",
              "tune_lower_95", "holdout_recall", "holdout_lower_95",
              "holdout_confirmed", "query_seconds", "build_seconds",
              "projected_queries", "projected_seconds")
    write_table(root / "recommendations.csv", selected, fields)
    baselines = []
    for r in selected:
        group = [item for item in results if
                 item["dataset"] == r["dataset"] and
                 item["scope"] == r["scope"] and
                 item["shard_rows"] == r["shard_rows"] and
                 item["k"] == r["k"]]
        if not group:
            continue
        policy = group[0]
        observed = lookup.get((r["dataset"], r["scope"],
            r["shard_rows"], r["k"], policy["faissr_m"],
            policy["faissr_ef_construction"],
            policy["faissr_ef_search"], "holdout"))
        baselines.append(dict(dataset=r["dataset"], scope=r["scope"],
            shard_rows=r["shard_rows"], k=r["k"],
            faissr_m=policy["faissr_m"],
            faissr_ef_construction=policy["faissr_ef_construction"],
            faissr_ef_search=policy["faissr_ef_search"],
            faissr_rule=policy["faissr_rule"],
            status="measured" if observed else "outside_search_grid",
            holdout_recall=observed["mean_recall"] if observed else "",
            holdout_lower_95=(observed["lower_95_recall"]
                              if observed else "")))
    write_table(root / "faissr_baselines.csv", baselines,
        ("dataset", "scope", "shard_rows", "k", "faissr_m",
         "faissr_ef_construction", "faissr_ef_search", "faissr_rule",
         "status", "holdout_recall", "holdout_lower_95"))
    pareto = []
    amortized = []
    for group in selected:
        sample = [item for item in results if
            item["dataset"] == group["dataset"] and
            item["scope"] == group["scope"] and
            item["shard_rows"] == group["shard_rows"] and
            item["k"] == group["k"] and item["split"] == "holdout"]
        def vector(item):
            return (-float(item["mean_recall"]),
                    float(item["query_seconds"]),
                    float(item["build_seconds"]),
                    float(item["rss_peak_bytes"]))
        for item in sample:
            here = vector(item)
            dominated = any(
                all(a <= b for a, b in zip(vector(other), here)) and
                any(a < b for a, b in zip(vector(other), here))
                for other in sample if other is not item)
            if not dominated:
                pareto.append({field: item[field] for field in
                    ("dataset", "scope", "shard_rows", "k", "m",
                     "ef_construction", "ef_search", "mean_recall",
                     "query_seconds", "build_seconds", "rss_peak_bytes",
                     "hostname")})
        eligible = [item for item in sample if
            float(lookup[key(item)[:-1] +
                ("tune",)]["lower_95_recall"]) >= 0.99]
        for item in eligible:
            for queries in (() if group["scope"] == "pilot" else
                            (1000, 10000, 1000000)):
                projected = projected_seconds(item, queries)
                amortized.append(dict(dataset=group["dataset"],
                    scope=group["scope"], shard_rows=group["shard_rows"],
                    k=group["k"], projected_queries=queries,
                    m=item["m"],
                    ef_construction=item["ef_construction"],
                    ef_search=item["ef_search"],
                    observed_holdout_recall=item["mean_recall"],
                    projected_seconds=projected))
    write_table(root / "pareto_points.csv", pareto,
        ("dataset", "scope", "shard_rows", "k", "m",
         "ef_construction", "ef_search", "mean_recall",
         "query_seconds", "build_seconds", "rss_peak_bytes", "hostname"))
    write_table(root / "amortized_estimates.csv", amortized,
        ("dataset", "scope", "shard_rows", "k", "projected_queries",
         "m", "ef_construction", "ef_search",
         "observed_holdout_recall", "projected_seconds"))
    transfer = []
    for r in selected:
        if (r["scope"] != "pilot" or
                r["status"] != "provisional_speed_candidate"):
            continue
        match = lookup.get((r["dataset"], "scale", "20000", r["k"],
                            r["m"], r["ef_construction"],
                            r["ef_search"], "holdout"))
        transfer.append(dict(dataset=r["dataset"], k=r["k"],
            pilot_m=r["m"], pilot_ef_construction=r["ef_construction"],
            pilot_ef_search=r["ef_search"],
            pilot_holdout_recall=r["holdout_recall"],
            scale_holdout_recall=match["mean_recall"] if match else "",
            scale_holdout_lower_95=(match["lower_95_recall"]
                                    if match else "")))
    write_table(root / "pilot_transfer.csv", transfer,
                ("dataset", "k", "pilot_m", "pilot_ef_construction",
                 "pilot_ef_search", "pilot_holdout_recall",
                 "scale_holdout_recall", "scale_holdout_lower_95"))
    report = {"complete": not failures, "truth_cases": len(truth),
              "sweep_cases": len(cases), "sweep_rows": len(results),
              "no_candidate_groups": sum(r["status"] == "no_recall_099"
                                         for r in selected),
              "unconfirmed_speed_candidates": sum(
                  r["status"] == "provisional_speed_candidate" and
                  not r["holdout_confirmed"] for r in selected),
              "failures": failures,
              "note": "Recall is sampled; no default policy change is implied."}
    (root / "audit.json").write_text(json.dumps(report, indent=2) + "\n")
    with (root / "stages.tsv").open("a", encoding="utf-8") as stream:
        stream.write(f'audit\t-\t{"completed" if not failures else "failed"}\n')
    print(json.dumps(report, indent=2))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
