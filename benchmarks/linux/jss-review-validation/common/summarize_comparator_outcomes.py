#!/usr/bin/env python3
"""Reconcile comparator status files with final Slurm task states."""

import csv
import pathlib
import sys


FIELDS = (
    "dataset", "method", "comparator_mode", "status", "reason",
    "source", "job_key", "exit_code", "timeout_seconds",
    "scheduler_state",
)


def first_row(path):
    if not path.is_file():
        return {}
    with path.open(newline="") as handle:
        return next(csv.DictReader(handle), {})


def scheduler_rows(path):
    if not path.is_file():
        return {}
    with path.open(newline="") as handle:
        return {
            row["job_key"]: row for row in csv.DictReader(
                handle, delimiter="\t"
            )
        }


def classify(worker, scheduler):
    state = scheduler.get("state", "UNKNOWN").split()[0].upper()
    status = worker.get("status", "").lower()
    reason = worker.get("error", "") or ""
    if state.startswith("OUT_OF_MEMORY"):
        return "memory_limit", "Slurm OUT_OF_MEMORY", "slurm"
    if state.startswith("TIMEOUT"):
        return "timeout", "Slurm TIMEOUT", "slurm"
    if state.startswith("CANCELLED"):
        return "cancelled", f"Slurm {state}", "slurm"
    if status == "timeout":
        return "timeout", reason, "worker"
    if status == "killed_unclassified":
        return status, reason, "worker"
    if state not in ("UNKNOWN", "COMPLETED"):
        return "failed", f"Slurm {state}; {reason}".strip("; "), "slurm"
    if status:
        return status, reason, "worker"
    return "missing_status", "No worker status file", "audit"


def summarize(root, task_audit):
    scheduler = scheduler_rows(task_audit)
    rows = []
    for identity_path in root.glob(
        "workflow_comparators*/**/task_identity.csv"
    ):
        identity = first_row(identity_path)
        worker = first_row(identity_path.with_name("status.csv"))
        task = scheduler.get(identity.get("job_key", ""), {})
        status, reason, source = classify(worker, task)
        rows.append({
            "dataset": identity.get("dataset", ""),
            "method": identity.get("method", ""),
            "comparator_mode": identity.get("mode", ""),
            "status": status,
            "reason": reason,
            "source": source,
            "job_key": identity.get("job_key", ""),
            "exit_code": task.get("exit_code", "") or
                worker.get("exit_code", ""),
            "timeout_seconds": identity.get("timeout_seconds", ""),
            "scheduler_state": task.get("state", "UNKNOWN"),
        })
    output = root / "aggregate" / "workflow_comparator_outcomes.csv"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(sorted(rows, key=lambda row: (
            row["comparator_mode"], row["dataset"], row["method"]
        )))
    print(f"Wrote {len(rows)} comparator outcomes to {output}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: summarize_comparator_outcomes.py ROOT TASK_AUDIT")
    summarize(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
