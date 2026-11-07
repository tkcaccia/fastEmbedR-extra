#!/usr/bin/env python3
"""Audit the three-case mass41 CPU4 resident pilot."""

import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess

import audit_scaling as core
from audit_dataset_wave_v3 import parse_sacct


EXPECTED = ((42, "Leiden", 0), (43, "Louvain", 0), (44, "PCA", 2))


def selected_cases(root, cases):
    by_id = {case["case_id"]: case for case in cases}
    wave = (root / "wave_cpu4.txt").read_text().splitlines()
    if len(wave) != 77:
        raise ValueError("CPU4 roster length differs")
    selected = []
    for index, method, dimensions in EXPECTED:
        case = by_id[wave[index]]
        if (case["dataset"] != "mass41" or case["method"] != method or
                case["dimensions"] != dimensions or case["cores"] != 4 or
                case["backend"] != "cpu" or case["spill"] or
                case["storage_mode"] != "in_memory" or
                case["expected_rows"] != 965282 or
                case["expected_columns"] != 14):
            raise ValueError("mass41 pilot roster differs")
        selected.append((index, case))
    if len({case["case_id"] for _, case in selected}) != 3:
        raise ValueError("Duplicate mass41 pilot case")
    return selected


def audit(root, job_id):
    if not job_id.isdecimal():
        raise ValueError("One numeric Slurm array ID is required")
    core.HERE = root
    cases = [json.loads(line) for line in
             (root / "cases.jsonl").read_text().splitlines()]
    if not core.plan_identity(cases):
        raise ValueError("Full v3 plan identity differs")
    selected = selected_cases(root, cases)
    raw = subprocess.run(
        ["sacct", "-j", job_id, "-X", "-n", "-P",
         "-o", "JobID,JobIDRaw,State,ExitCode"],
        check=True, capture_output=True, text=True).stdout
    tasks = parse_sacct(raw, [job_id])
    routes_sha = core.sha256(root / "routes.json")
    worker_sha = core.sha256(root / "matched_worker.R")
    rows = []
    for index, case in selected:
        task = tasks.get((job_id, index))
        actual_id = task[0] if task else None
        state = task[1:] if task else None
        jobs = {actual_id: state} if actual_id else {}
        row = core.inspect_case(case, root / "results", jobs,
                                routes_sha, worker_sha)
        if state != ("COMPLETED", "0:0"):
            row["status"] = "audit_failed"
            row.setdefault("issues", []).append("scheduler_task_outcome")
        provenance_file = (root / "results" / case["case_id"] /
                           "provenance.json")
        if provenance_file.is_file():
            provenance = json.loads(provenance_file.read_text())
            if (provenance.get("slurm_job_id") != actual_id or
                    provenance.get("slurm_array_task_id") != str(index)):
                row["status"] = "audit_failed"
                row.setdefault("issues", []).append("wrong_array_task")
        row.update(array_index=index, numeric_job_id=actual_id,
                   scheduler_state=state)
        rows.append(row)
    counts = dict(Counter(row["status"] for row in rows))
    return {"benchmark_source": "matched-main-535d071-20261107-v3",
            "package_commit": core.PACKAGE_COMMIT,
            "dataset": "mass41", "cores": 4, "array_job_id": job_id,
            "planned": 3, "counts": counts, "cases": rows,
            "status": "passed" if counts == {"audited": 3} else "failed"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cohort-root", type=Path, required=True)
    parser.add_argument("--job", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.cohort_root, args.job)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"],
                      "counts": report["counts"]}, sort_keys=True))
    raise SystemExit(0 if report["status"] == "passed" else 1)
