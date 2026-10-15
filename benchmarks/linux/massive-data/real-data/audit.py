#!/usr/bin/env python3
"""Audit matched classic/file-backed runs with explicit failure classes."""

import csv
import json
import subprocess
import sys
from pathlib import Path


def read_csv(path, delimiter=","):
    if not path.is_file():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle, delimiter=delimiter))


def sacct_states(root):
    jobs = read_csv(root / "jobs.tsv", "\t")
    ids = [row["job_id"] for row in jobs if row["lane"] != "audit"]
    result = subprocess.run(
        ["sacct", "-X", "-j", ",".join(ids), "-P", "-n",
         "-o", "JobID,State,ExitCode"], text=True, capture_output=True)
    if result.returncode:
        return {}
    return {parts[0]: parts[1] for line in result.stdout.splitlines()
            if len(parts := line.split("|")) >= 3}


def task_ids(root, dataset):
    mapping = {}
    for job in read_csv(root / "jobs.tsv", "\t"):
        if job["dataset"] != dataset or job["lane"] in ("prep", "audit"):
            continue
        cases = read_csv(root / dataset /
                         f"cases_{job['lane']}.tsv", "\t")
        for index, case in enumerate(cases):
            task = job["job_id"] if "cuda" in job["lane"] else \
                f"{job['job_id']}_{index}"
            mapping[case["name"]] = task
    return mapping


def wall_time(path):
    if not path.is_file():
        return None, None
    wall = rss = None
    for line in path.read_text().splitlines():
        if "Elapsed (wall clock) time" in line:
            value = line.rsplit(": ", 1)[-1]
            parts = [float(part) for part in value.split(":")]
            wall = sum(part * 60 ** i for i, part in
                       enumerate(reversed(parts)))
        if "Maximum resident set size (kbytes)" in line:
            rss = int(line.rsplit(": ", 1)[-1]) * 1024
    return wall, rss


def classify(code, state):
    if code == "0":
        return "ok"
    if code == "124":
        return "time_limit"
    if "OUT_OF_MEMORY" in state:
        return "memory_limit"
    if "TIMEOUT" in state:
        return "time_limit"
    if "CANCELLED" in state:
        return "cancelled"
    if code is None:
        return "missing_output"
    return "failed"


def audit(root, dataset):
    states = sacct_states(root)
    ids = task_ids(root, dataset)
    results = []
    for case in read_csv(root / dataset / "cases.tsv", "\t"):
        path = root / dataset / "results" / case["name"]
        status = read_csv(path / "status.tsv", "\t")
        code = status[0]["exit_code"] if status else None
        state = states.get(ids.get(case["name"], ""), "UNKNOWN")
        outcome = classify(code, state)
        if case["backend"] == "cpu" and "OUT_OF_MEMORY" in state:
            outcome = "memory_limit"
        if case["backend"] == "cpu" and "TIMEOUT" in state:
            outcome = "time_limit"
        metrics = read_csv(path / "metrics.csv")
        gpu = read_csv(path / "gpu_memory.csv")
        visual = read_csv(path / "visual_manifest.csv")
        quality = read_csv(path / "quality.csv")
        seconds, rss = wall_time(path / "time.txt")
        if outcome == "ok" and (not metrics or seconds is None or
                                rss is None):
            outcome = "missing_metrics"
        if outcome == "ok" and metrics[0].get("status") != "ok":
            outcome = "fit_reported_failure"
        if outcome == "ok" and case["mode"] != "cluster" and (
                not visual or
                int(visual[0]["plotted_rows"]) != int(case["rows"]) or
                not quality):
            outcome = "missing_visual_or_quality"
        if outcome == "ok" and case["backend"] == "cuda" and (
                not gpu or gpu[0]["status"] != "ok"):
            outcome = "missing_vram_measurement"
        if outcome == "ok" and case["devices"] == "0,1" and (
                not gpu or int(gpu[0]["device_count"]) != 2):
            outcome = "two_gpu_not_observed"
        results.append({**case, "job_id": ids.get(case["name"], ""),
            "slurm_state": state, "exit_code": code or "",
            "outcome": outcome, "wall_seconds": seconds or "",
            "rss_peak_bytes": rss or "",
            "vram_peak_bytes": gpu[0]["peak_bytes"] if gpu else "",
            "vram_device_count": gpu[0]["device_count"] if gpu else "",
            "plotted_rows": visual[0]["plotted_rows"] if visual else "",
            "trustworthiness": quality[0].get("trustworthiness", "")
            if quality else "",
            "knn_preservation_30": quality[0].get(
                "knn_preservation_30", "") if quality else "",
            "fit_error": metrics[0].get("error", "") if metrics else ""})
    with (root / dataset / "all_cases.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, results[0])
        writer.writeheader()
        writer.writerows(results)
    pairs = []
    for current in results:
        if current["route"] != "file" or current["outcome"] != "ok":
            continue
        classic = next((row for row in results if row["route"] == "classic"
            and all(row[key] == current[key] for key in
                    ("backend", "cores", "mode")) and
            row["outcome"] == "ok"), None)
        if classic is None:
            continue
        pairs.append(dict(dataset=dataset, backend=current["backend"],
            cores=current["cores"], mode=current["mode"],
            classic_seconds=classic["wall_seconds"],
            file_seconds=current["wall_seconds"],
            classic_rss=classic["rss_peak_bytes"],
            file_rss=current["rss_peak_bytes"],
            classic_vram=classic["vram_peak_bytes"],
            file_vram=current["vram_peak_bytes"],
            classic_trustworthiness=classic["trustworthiness"],
            file_trustworthiness=current["trustworthiness"],
            classic_knn_preservation_30=classic["knn_preservation_30"],
            file_knn_preservation_30=current["knn_preservation_30"],
            speed_ratio=float(classic["wall_seconds"]) /
                        float(current["wall_seconds"]),
            rss_ratio=float(classic["rss_peak_bytes"]) /
                      float(current["rss_peak_bytes"])))
    with (root / dataset / "matched_pairs.csv").open("w", newline="") as h:
        if pairs:
            writer = csv.DictWriter(h, pairs[0])
            writer.writeheader()
            writer.writerows(pairs)
    report = dict(dataset=dataset, cases=len(results),
        successes=sum(row["outcome"] == "ok" for row in results),
        matched_pairs=len(pairs),
        issues=[{key: row[key] for key in
                ("name", "outcome", "slurm_state", "exit_code")}
                for row in results if row["outcome"] != "ok"])
    report["status"] = "PASS" if not report["issues"] else "PARTIAL"
    (root / dataset / "audit.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    audit(Path(sys.argv[1]), sys.argv[2])
