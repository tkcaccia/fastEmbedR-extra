#!/usr/bin/env python3
"""Focused regression checks for comparator outcome classification."""

import csv
import pathlib
import tempfile

from summarize_comparator_outcomes import classify, summarize


assert classify(
    {"status": "timeout"}, {"state": "FAILED"}
)[0] == "timeout"
assert classify(
    {"status": "killed_unclassified"}, {"state": "FAILED"}
)[0] == "killed_unclassified"
assert classify(
    {"status": "killed_unclassified"}, {"state": "OUT_OF_MEMORY"}
)[0] == "memory_limit"
assert classify(
    {"status": "success"}, {"state": "FAILED"}
)[0] == "failed"

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    task = root / "workflow_comparators/r_cpu/COIL20/r_umap"
    task.mkdir(parents=True)
    (task / "task_identity.csv").write_text(
        "job_key,mode,dataset,method,timeout_seconds\n"
        "123_0,r_cpu,COIL20,r_umap,7200\n"
    )
    (task / "status.csv").write_text(
        "status,error\nkilled_unclassified,SIGKILL\n"
    )
    audit = root / "job_audit_tasks.tsv"
    audit.write_text(
        "job_key\tstate\texit_code\n"
        "123_0\tOUT_OF_MEMORY\t0:9\n"
    )
    summarize(root, audit)
    output = root / "aggregate/workflow_comparator_outcomes.csv"
    with output.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 1
    assert rows[0]["status"] == "memory_limit"
    assert rows[0]["source"] == "slurm"

print("Comparator outcome classification: PASS")
