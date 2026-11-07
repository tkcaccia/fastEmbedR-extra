#!/usr/bin/env python3
"""Audit one complete seven-method resident CPU dataset wave."""

import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess

import audit_scaling as core


CORES = (1, 2, 4, 8, 16, 32)


def parse_sacct(output, job_ids):
    allowed = set(job_ids)
    tasks = {}
    for line in output.splitlines():
        parts = line.split("|")
        if len(parts) != 4 or "_" not in parts[0]:
            continue
        job_id, index = parts[0].split("_", 1)
        if (job_id in allowed and index.isdecimal() and
                parts[1].isdecimal()):
            tasks[(job_id, int(index))] = (parts[1], parts[2], parts[3])
    return tasks


def audit(root, dataset, job_ids):
    if len(job_ids) != len(CORES) or len(set(job_ids)) != len(CORES) or \
            any(not job.isdecimal() for job in job_ids):
        raise ValueError("Provide six distinct numeric Slurm job IDs")
    core.HERE = root
    cases = [json.loads(line) for line in
             (root / "cases.jsonl").read_text().splitlines()]
    if not core.plan_identity(cases):
        raise ValueError("Full v3 plan identity differs")
    case_by_id = {case["case_id"]: case for case in cases}
    raw = subprocess.run(
        ["sacct", "-j", ",".join(job_ids), "-X", "-n", "-P",
         "-o", "JobID,JobIDRaw,State,ExitCode"],
        check=True, capture_output=True, text=True).stdout
    task_states = parse_sacct(raw, job_ids)
    routes_sha = core.sha256(root / "routes.json")
    worker_sha = core.sha256(root / "matched_worker.R")
    rows = []
    for cores, job_id in zip(CORES, job_ids):
        wave = (root / f"wave_cpu{cores}.txt").read_text().splitlines()
        selected = [(index, case_by_id[name])
                    for index, name in enumerate(wave)
                    if case_by_id[name]["dataset"] == dataset]
        if len(wave) != 77 or len(selected) != 7 or \
                {case["method"] for _, case in selected} != \
                {"PCA", "t-SNE", "UMAP", "Leiden", "Louvain"}:
            raise ValueError(f"Unexpected {dataset} roster for CPU{cores}")
        for index, case in selected:
            task = task_states.get((job_id, index))
            actual_id = task[0] if task else None
            expected_state = task[1:] if task else None
            jobs = ({actual_id: expected_state}
                    if actual_id is not None else {})
            row = core.inspect_case(case, root / "results", jobs,
                                    routes_sha, worker_sha)
            if expected_state != ("COMPLETED", "0:0"):
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
            row.update(cores=cores, array_index=index,
                       array_job_id=job_id, numeric_job_id=actual_id,
                       scheduler_state=expected_state)
            rows.append(row)
    counts = dict(Counter(row["status"] for row in rows))
    return {"benchmark_source": "matched-main-535d071-20261107-v3",
            "package_commit": core.PACKAGE_COMMIT,
            "dataset": dataset, "job_ids_by_core": dict(zip(CORES, job_ids)),
            "planned": 42, "counts": counts, "cases": rows,
            "status": "passed" if counts == {"audited": 42} else "failed"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cohort-root", type=Path, required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--jobs", nargs=6, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.cohort_root, args.dataset, args.jobs)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"],
                      "counts": report["counts"]}, sort_keys=True))
    raise SystemExit(0 if report["status"] == "passed" else 1)
