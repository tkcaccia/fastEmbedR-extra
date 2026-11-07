#!/usr/bin/env python3
"""Audit one exact seven-method CPU pilot without assuming array root IDs."""

import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess

import audit_scaling as core
from audit_dataset_wave_v3 import parse_sacct


CORES = (1, 2, 4, 8, 16, 32)


def pilot_cases(root, dataset, cores, cases):
    by_id = {case["case_id"]: case for case in cases}
    wave = (root / f"wave_cpu{cores}.txt").read_text().splitlines()
    selected = [(index, by_id[name]) for index, name in enumerate(wave)
                if by_id[name]["dataset"] == dataset]
    if (len(wave) != 77 or len(selected) != 7 or
            {case["method"] for _, case in selected} !=
            {"PCA", "t-SNE", "UMAP", "Leiden", "Louvain"} or
            any(case["cores"] != cores for _, case in selected)):
        raise ValueError("The exact seven-method pilot roster differs")
    return selected


def audit(root, dataset, cores, job_id):
    if cores not in CORES or not job_id.isdecimal():
        raise ValueError("Unreviewed pilot core count or Slurm ID")
    core.HERE = root
    cases = [json.loads(line) for line in
             (root / "cases.jsonl").read_text().splitlines()]
    if not core.plan_identity(cases):
        raise ValueError("Full v2 plan identity differs")
    selected = pilot_cases(root, dataset, cores, cases)
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
        jobs = ({actual_id: state} if actual_id else {})
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
    return {"benchmark_source": "matched-main-535d071-20261107-v2",
            "package_commit": core.PACKAGE_COMMIT,
            "dataset": dataset, "cores": cores, "array_job_id": job_id,
            "planned": 7, "counts": counts, "cases": rows,
            "status": "passed" if counts == {"audited": 7} else "failed"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cohort-root", type=Path, required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--cores", type=int, required=True)
    parser.add_argument("--job", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.cohort_root, args.dataset, args.cores, args.job)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"],
                      "counts": report["counts"]}, sort_keys=True))
    raise SystemExit(0 if report["status"] == "passed" else 1)
