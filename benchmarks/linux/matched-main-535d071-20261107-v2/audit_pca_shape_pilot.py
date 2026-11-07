#!/usr/bin/env python3
"""Audit only the two versioned flow18 PCA shape-limit pilots."""

import json
from pathlib import Path
import subprocess
import sys

import audit_scaling as core


EXPECTED = {16: "1606370", 32: "1606371"}


def scheduler_outcomes():
    result = subprocess.run(
        ["sacct", "-j", ",".join(EXPECTED.values()), "-X", "-n", "-P",
         "-o", "JobID,JobName,State,ExitCode"],
        check=True, capture_output=True, text=True)
    jobs = {}
    for line in result.stdout.splitlines():
        parts = line.split("|")
        if len(parts) != 4:
            continue
        job = parts[0].split("_", 1)
        if (job[0] in EXPECTED.values() and len(job) == 2 and
                job[1] == "16"):
            jobs[job[0]] = (parts[2], parts[3])
    if set(jobs) != set(EXPECTED.values()):
        raise ValueError("The two exact Slurm array tasks are not accounted for")
    return jobs


def audit(root):
    core.HERE = root
    cases = [json.loads(line) for line in
             (root / "cases.jsonl").read_text().splitlines()]
    if not core.plan_identity(cases):
        raise ValueError("The full 462-case v2 plan identity differs")
    jobs = scheduler_outcomes()
    rows = []
    for cores, job_id in EXPECTED.items():
        case_id = f"flow18_pca_cpu{cores}_d2_s4_matched_535d071"
        case = json.loads((root / "cases" / (case_id + ".json")).read_text())
        if (case not in cases or case["dataset"] != "flow18" or
                case["method"] != "PCA" or case["cores"] != cores or
                case["expected_columns"] != 11 or
                case["storage_mode"] != "in_memory" or case["spill"]):
            raise ValueError(f"Unexpected v2 pilot manifest: {case_id}")
        row = core.inspect_case(case, root / "results", jobs,
                                core.sha256(root / "routes.json"),
                                core.sha256(root / "matched_worker.R"))
        folder = root / "results" / case_id
        metrics = json.loads((folder / "metrics.json").read_text())
        memory = json.loads((folder / "memory.json").read_text())
        row.update(requested_cores=cores,
                   native_effective_cores=metrics.get("cores_effective"),
                   blas_observed_cores=metrics.get("pca_blas_cores_observed"),
                   fit_seconds=metrics.get("fit_seconds"),
                   peak_ram_bytes=memory.get("peak_ram_bytes"))
        if row.get("job_id") != job_id:
            row["status"] = "audit_failed"
            row.setdefault("issues", []).append("wrong_pilot_job")
        rows.append(row)
    return {"benchmark_source": "matched-main-535d071-20261107-v2",
            "package_commit": core.PACKAGE_COMMIT, "cases": rows,
            "status": "passed" if all(row["status"] == "audited"
                                      for row in rows) else "failed"}


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: audit_pca_shape_pilot.py ROOT REPORT")
    report = audit(Path(sys.argv[1]))
    Path(sys.argv[2]).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"],
                      "cases": report["cases"]}, sort_keys=True))
    raise SystemExit(0 if report["status"] == "passed" else 1)
