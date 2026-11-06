"""Read-only audit of the resident CPU cohort's small result manifests."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path


HERE = Path(__file__).resolve().parent
PACKAGE_COMMIT = "7c68bc2a48ff3f98d07f216db9601047951827fd"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def accounting(path: Path) -> dict[str, tuple[str, str]]:
    jobs = {}
    for line in path.read_text().splitlines():
        parts = line.split("|")
        if len(parts) == 4 and parts[0].isdecimal():
            jobs[parts[0]] = (parts[2], parts[3])
    return jobs


def finite_nonnegative(value: object) -> bool:
    return (type(value) in (int, float) and math.isfinite(value)
            and value >= 0)


def inspect_case(case: dict, results: Path, jobs: dict,
                 routes_sha: str, worker_sha: str) -> dict:
    case_id = case["case_id"]
    folder = results / case_id
    if not folder.is_dir():
        return {"case_id": case_id, "status": "missing_result"}
    issues = []
    try:
        provenance = json.loads((folder / "provenance.json").read_text())
        identity = json.loads((folder / "input_identity.json").read_text())
        memory = json.loads((folder / "memory.json").read_text())
        metrics = json.loads((folder / "metrics.json").read_text())
    except (OSError, ValueError, TypeError) as error:
        return {"case_id": case_id, "status": "incomplete_result",
                "issues": [str(error)]}
    if not all(isinstance(item, dict) for item in
               (provenance, identity, memory, metrics)):
        return {"case_id": case_id, "status": "incomplete_result",
                "issues": ["Malformed result manifest."]}
    case_file = HERE / "cases" / f"{case_id}.json"
    if (provenance.get("case_sha256") != sha256(case_file) or
            provenance.get("routes_sha256") != routes_sha or
            provenance.get("worker_sha256") != worker_sha or
            provenance.get("package_commit") != PACKAGE_COMMIT):
        issues.append("source_identity")
    if provenance.get("status") != "completed" or \
            provenance.get("exit_code") != 0:
        issues.append("runner_status")
    if (identity.get("status") != "verified" or
            identity.get("actual_sha256") != case["input_sha256"] or
            identity.get("expected_sha256") != case["input_sha256"] or
            not finite_nonnegative(identity.get("verification_seconds")) or
            not isinstance(identity.get("size_bytes"), int) or
            identity["size_bytes"] < 1):
        issues.append("input_identity")
    after = memory.get("after")
    if (memory.get("scope") != "slurm_job_cgroup" or
            not isinstance(memory.get("peak_ram_bytes"), int) or
            memory["peak_ram_bytes"] < 1 or
            not isinstance(after, dict) or
            after.get("job_id") !=
            provenance.get("slurm_job_id")):
        issues.append("memory_scope")
    if (metrics.get("case_id") != case_id or
            metrics.get("dataset") != case["dataset"] or
            metrics.get("method") != case["method"] or
            metrics.get("n_rows") != case["expected_rows"] or
            metrics.get("n_columns") != case["expected_columns"] or
            metrics.get("dimensions") != case["dimensions"] or
            metrics.get("cores") != case["cores"] or
            metrics.get("input_sha256") != case["input_sha256"] or
            not str(metrics.get("observed_backend", "")).startswith("cpu")):
        issues.append("science_identity")
    for field in ("load_seconds", "preprocess_seconds", "graph_seconds",
                  "fit_seconds", "quality_seconds", "write_seconds"):
        if not finite_nonnegative(metrics.get(field)):
            issues.append("invalid_" + field)
    quality = metrics.get("quality")
    if not isinstance(quality, dict):
        quality = {}
    if case["method"] in ("t-SNE", "UMAP"):
        if any(not finite_nonnegative(quality.get(key)) or quality[key] > 1
               for key in ("trustworthiness", "label_accuracy")):
            issues.append("invalid_embedding_quality")
    elif case["method"] in ("Leiden", "Louvain"):
        if (not isinstance(quality.get("communities"), int) or
                quality["communities"] < 1 or
                type(quality.get("modularity")) not in (int, float) or
                not math.isfinite(quality["modularity"]) or
                not -1 <= quality["modularity"] <= 1 or
                type(quality.get("ari")) not in (int, float) or
                not math.isfinite(quality["ari"]) or
                not -1 <= quality["ari"] <= 1):
            issues.append("invalid_clustering_quality")
    elif case["method"] == "PCA":
        values = quality.get("singular_values")
        if not isinstance(values, list) or len(values) != case["dimensions"] or \
                any(not finite_nonnegative(value) for value in values):
            issues.append("invalid_pca_quality")
    output = folder / "output.rds"
    if not output.is_file() or output.stat().st_size < 1:
        issues.append("output_missing")
    job_id = provenance.get("slurm_job_id")
    if jobs.get(job_id) != ("COMPLETED", "0:0"):
        issues.append("scheduler_outcome")
    return {"case_id": case_id,
            "status": "audited" if not issues else "audit_failed",
            "issues": issues, "job_id": job_id}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--accounting", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    cases = [json.loads(line) for line in
             (HERE / "cases.jsonl").read_text().splitlines()]
    jobs = accounting(args.accounting)
    rows = [inspect_case(case, args.results, jobs,
                         sha256(HERE / "routes.json"),
                         sha256(HERE / "matched_worker.R"))
            for case in cases]
    summary = {"package_commit": PACKAGE_COMMIT,
               "benchmark_source": "matched-main-7c68bc2-20261106-v1",
               "counts": dict(Counter(row["status"] for row in rows)),
               "cases": rows}
    args.output.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary["counts"], sort_keys=True))
    return 0 if summary["counts"] == {"audited": len(cases)} else 1


if __name__ == "__main__":
    raise SystemExit(main())
