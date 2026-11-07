#!/usr/bin/env python3
"""Audit the corrected 550-iteration resident COIL20 t-SNE pilot."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import subprocess


METHODS = ("rtsne", "fitsne")
INPUT_SHA = "8e53030869bcfbc228edc06ca970e69b78ddae13fb188327e8899194d5841d66"
IMAGE_SHA = "15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2"
PACKAGE_COMMIT = "535d071849945db3fa550d3c50f80633b91748cc"


def task_states(text: str, root_job: str) -> dict[int, tuple[str, str, str]]:
    states = {}
    for line in text.splitlines():
        parts = line.split("|")
        if len(parts) != 4 or not parts[0].startswith(root_job + "_"):
            continue
        index = parts[0][len(root_job) + 1:]
        if index.isdecimal() and parts[1].isdecimal():
            states[int(index)] = (parts[1], parts[2], parts[3])
    return states


def bounded(value, low=0, high=float("inf")) -> bool:
    return (type(value) in (int, float) and math.isfinite(value)
            and low <= value <= high)


def audit(root: Path, root_job: str, sacct_text: str) -> dict:
    if not root_job.isdecimal():
        raise ValueError("Slurm root job ID must be numeric")
    worker = root / "coil20_r_tsne_schedule550_worker.R"
    worker_sha = hashlib.sha256(worker.read_bytes()).hexdigest()
    states = task_states(sacct_text, root_job)
    rows = []
    for index, method in enumerate(METHODS):
        task = states.get(index)
        folder = root / "results" / f"coil20_{method}_cpu4_d2_s4_schedule550"
        issues = []
        if task is None or task[1:] != ("COMPLETED", "0:0"):
            issues.append("scheduler_task_outcome")
        try:
            metrics = json.loads((folder / "metrics.json").read_text())
        except (OSError, ValueError):
            metrics = None
            issues.append("metrics_missing")
        if not (folder / "layout.rds").is_file() or \
                (folder / "layout.rds").stat().st_size < 1:
            issues.append("layout_missing")
        if isinstance(metrics, dict):
            expected = {
                "dataset": "COIL20", "method": method,
                "backend": "cpu", "requested_cores": 4,
                "seed": 4, "dimensions": 2,
                "n_rows": 1440, "n_columns": 16384,
                "preprocessing_rank": 30,
                "source_precision": "float32",
                "comparator_precision": "double",
                "input_sha256": INPUT_SHA,
                "image_sha256": IMAGE_SHA,
                "package_commit": PACKAGE_COMMIT,
                "worker_sha256": worker_sha,
                "output_file": "layout.rds",
                "slurm_job_id": task[0] if task else None,
                "slurm_array_task_id": str(index),
                "early_exaggeration_iterations": 250,
                "normal_iterations": 300,
                "total_iterations": 550,
            }
            if any(metrics.get(key) != value for key, value in
                   expected.items()):
                issues.append("source_or_case_identity")
            if not isinstance(metrics.get("comparator_version"), str) or \
                    not metrics["comparator_version"]:
                issues.append("comparator_version")
            for field in ("load_seconds", "preprocess_seconds",
                          "conversion_seconds", "fit_seconds",
                          "quality_seconds", "write_seconds"):
                if not bounded(metrics.get(field),
                               low=1e-12 if field == "fit_seconds" else 0):
                    issues.append("invalid_" + field)
            quality = metrics.get("quality")
            if not isinstance(quality, dict) or any(
                    not bounded(quality.get(field), 0, 1)
                    for field in ("trustworthiness", "label_accuracy")):
                issues.append("invalid_quality")
        rows.append({"index": index, "method": method,
                     "numeric_job_id": task[0] if task else None,
                     "scheduler_state": task[1:] if task else None,
                     "status": "audited" if not issues else "audit_failed",
                     "issues": issues})
    counts = dict(Counter(row["status"] for row in rows))
    return {"array_job_id": root_job, "package_commit": PACKAGE_COMMIT,
            "worker_sha256": worker_sha, "planned": len(METHODS),
            "counts": counts, "cases": rows,
            "status": "passed" if counts == {"audited": 2} else "failed"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--job", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = subprocess.run(
        ["sacct", "-j", args.job, "-X", "-n", "-P",
         "-o", "JobID,JobIDRaw,State,ExitCode"],
        check=True, capture_output=True, text=True)
    report = audit(args.root, args.job, result.stdout)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"],
                      "counts": report["counts"]}, sort_keys=True))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
