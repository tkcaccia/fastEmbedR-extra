#!/usr/bin/env python3
"""Expand the source-locked matched CPU panel to its six core counts."""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys

from policy import load_jsonl, validate_plan


HERE = Path(__file__).resolve().parent
CORES = (1, 2, 4, 8, 16, 32)
PACKAGE_COMMIT = "535d071849945db3fa550d3c50f80633b91748cc"
REMOTE_ROOT = "/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v1"
IMAGE = ("/scratch/firenze/NN/singularity/release_535d071_20261107/"
         "fastembedr_535d071_20261107.sif")
IDENTITY = ("/scratch/firenze/NN/singularity/release_535d071_20261107/"
            "release_inputs/source-identity.txt")
EXPECTED_METHODS = frozenset({
    ("PCA", 2), ("t-SNE", 2), ("t-SNE", 3),
    ("UMAP", 2), ("UMAP", 3), ("Leiden", 0), ("Louvain", 0),
})


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expand_cases(source: list[dict], routes: dict) -> dict[int, list[dict]]:
    by_dataset = {}
    for case in source:
        if (case.get("cores") != 4 or case.get("backend") != "cpu" or
                case.get("gpus") != 0 or
                case.get("storage_mode") != "in_memory" or
                case.get("runtime_input") != "resident" or
                case.get("algorithm_state") != "resident" or
                case.get("fit_scope") != "all_rows_optimized" or
                case.get("spill") is not False or
                case.get("scientific_tests") != 1 or
                case.get("warmup_fits") != 0 or
                case.get("seed") != 4 or case.get("repetition") != 1 or
                not isinstance(case.get("expected_rows"), int) or
                case["expected_rows"] < 2 or
                not isinstance(case.get("expected_columns"), int) or
                case["expected_columns"] < 1 or
                not isinstance(case.get("input_sha256"), str) or
                not re.fullmatch(r"[0-9a-f]{64}",
                                 case["input_sha256"]) or
                not isinstance(case.get("case_id"), str) or
                case["case_id"].count("_cpu4_") != 1):
            raise ValueError("Source panel is not the reviewed resident CPU4 cohort")
        by_dataset.setdefault(case["dataset"], []).append(
            (case["method"], case["dimensions"]))
    if len(by_dataset) != 11 or any(
            len(methods) != 7 or set(methods) != EXPECTED_METHODS
            for methods in by_dataset.values()):
        raise ValueError("Source panel does not cover eleven datasets and seven methods")
    original = validate_plan(source, routes)
    if any(item["status"] != "eligible" for item in original):
        raise ValueError("Source panel contains an unqualified route")
    expanded = {}
    for cores in CORES:
        cases = []
        for case in source:
            next_case = copy.deepcopy(case)
            next_case["case_id"] = case["case_id"].replace(
                "_cpu4_", f"_cpu{cores}_", 1)
            next_case["cores"] = cores
            cases.append(next_case)
        verdicts = validate_plan(cases, routes)
        if any(item["status"] != "eligible" for item in verdicts):
            raise ValueError(f"CPU{cores} panel contains an unqualified route")
        expanded[cores] = cases
    all_ids = [case["case_id"] for cases in expanded.values()
               for case in cases]
    if len(all_ids) != len(set(all_ids)):
        raise ValueError("Scaling panel has duplicate case IDs")
    return expanded


def write_plan(destination: Path, expanded: dict[int, list[dict]]) -> None:
    if destination.exists():
        raise FileExistsError("Scaling destination must be new")
    destination.mkdir(parents=True)
    cases_dir = destination / "cases"
    cases_dir.mkdir()
    (destination / "logs").mkdir()
    for name in ("run_case.py", "policy.py", "routes.json"):
        shutil.copy2(HERE / name, destination / name)
    shutil.copy2(HERE / "matched_worker_scaling.R",
                 destination / "matched_worker.R")
    lines = []
    for cores, cases in expanded.items():
        names = []
        for case in cases:
            payload = json.dumps(case, sort_keys=True) + "\n"
            (cases_dir / (case["case_id"] + ".json")).write_text(payload)
            lines.append(payload)
            names.append(case["case_id"])
        (destination / f"wave_cpu{cores}.txt").write_text(
            "\n".join(names) + "\n")
        (destination / f"wave_cpu{cores}.sbatch").write_text(
            render_sbatch(cores))
    (destination / "cases.jsonl").write_text("".join(lines))
    summary = {
        "package_commit": PACKAGE_COMMIT,
        "benchmark_source": "matched-main-535d071-20261107-v1",
        "source_cases_sha256": digest(HERE / "cases.jsonl"),
        "source_routes_sha256": digest(HERE / "routes.json"),
        "planner_sha256": digest(HERE / "plan_scaling.py"),
        "matched_worker_sha256": digest(HERE / "matched_worker_scaling.R"),
        "matched_runner_sha256": digest(HERE / "run_case.py"),
        "staged_worker_sha256": digest(destination / "matched_worker.R"),
        "staged_runner_sha256": digest(destination / "run_case.py"),
        "scaling_cases_sha256": digest(destination / "cases.jsonl"),
        "cores": list(CORES),
        "cases_per_core": {str(core): len(cases)
                           for core, cases in expanded.items()},
        "wave_script_sha256": {
            str(core): digest(destination / f"wave_cpu{core}.sbatch")
            for core in CORES},
        "total_cases": sum(map(len, expanded.values())),
        "storage_mode": "in_memory",
        "spill": False,
        "scientific_tests_per_allocation": 1,
        "warmup_fits_per_allocation": 0,
    }
    (destination / "plan-summary.json").write_text(
        json.dumps(summary, sort_keys=True, indent=2) + "\n")


def render_sbatch(cores: int) -> str:
    if cores not in CORES:
        raise ValueError("Unreviewed CPU core count")
    template = """#!/bin/bash
#SBATCH --job-name=fer-matched-cpu@CORES@
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=@CORES@
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --array=0-76%1
#SBATCH --output=@ROOT@/logs/cpu@CORES@-%A_%a.out
#SBATCH --error=@ROOT@/logs/cpu@CORES@-%A_%a.err
set -Eeuo pipefail
root=@ROOT@
image=@IMAGE@
identity=@IDENTITY@
test -f "$image"
test -f "$identity"
grep -qx 'FastEmbedRCommit=@COMMIT@' "$identity"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
case_id=$(sed -n "$((SLURM_ARRAY_TASK_ID+1))p" "$root/wave_cpu@CORES@.txt")
[[ $case_id =~ ^[A-Za-z0-9_-]+$ ]]
case_file="$root/cases/$case_id.json"
test -f "$case_file"
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \\
  /opt/conda/bin/python "$root/run_case.py" "$case_file" \\
  /scratch/firenze/NN/Data "$root/results"
"""
    return (template.replace("@CORES@", str(cores))
            .replace("@ROOT@", REMOTE_ROOT)
            .replace("@IMAGE@", IMAGE)
            .replace("@IDENTITY@", IDENTITY)
            .replace("@COMMIT@", PACKAGE_COMMIT))


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        raise SystemExit("Usage: plan_scaling.py NEW_OUTPUT_DIR")
    source = load_jsonl(HERE / "cases.jsonl")
    routes = json.loads((HERE / "routes.json").read_text())
    expanded = expand_cases(source, routes)
    write_plan(Path(argv[0]), expanded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
