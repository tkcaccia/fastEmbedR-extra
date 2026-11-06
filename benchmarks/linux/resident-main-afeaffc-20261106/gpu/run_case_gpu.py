"""Run exactly one reviewed, resident fastEmbedR case in a Slurm allocation."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from policy import validate_case


HERE = Path(__file__).resolve().parent
ROUTES = HERE / "gpu_routes.json"
R_WORKER = HERE / "gpu_worker.R"
DEEP1B_LOADER = HERE / "deep1b_resident.R"
RSCRIPT = Path("/opt/r46/bin/Rscript")


def refuse(reason: str) -> int:
    print(json.dumps({"status": "policy_rejected", "reason": reason}),
          file=sys.stderr)
    return 78


def visible_gpu_count() -> int:
    visible = os.environ.get("CUDA_VISIBLE_DEVICES", "")
    if visible in ("", "NoDevFiles"):
        return 0
    return len([item for item in visible.split(",") if item.strip()])


def allocation_matches(case: dict) -> bool:
    if not os.environ.get("SLURM_JOB_ID", "").isdecimal():
        return False
    task_id = os.environ.get("SLURM_ARRAY_TASK_ID", "")
    if task_id and not task_id.isdecimal():
        return False
    if os.environ.get("SLURM_NTASKS", "1") != "1":
        return False
    try:
        cores = int(os.environ["SLURM_CPUS_PER_TASK"])
    except (KeyError, ValueError):
        return False
    return cores == case["cores"] and \
        visible_gpu_count() == case["gpus"]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def allocation_identity() -> str:
    job_id = os.environ["SLURM_JOB_ID"]
    task_id = os.environ.get("SLURM_ARRAY_TASK_ID", "")
    return f"{job_id}_{task_id}" if task_id else job_id


def claim_allocation(output_root: Path, allocation_id: str,
                     case_id: str) -> bool:
    """Atomically prevent a second case in this allocation."""
    output_root.mkdir(parents=True, exist_ok=True)
    marker = output_root / f".slurm-{allocation_id}.claim"
    try:
        with marker.open("x") as stream:
            json.dump({"allocation_id": allocation_id,
                       "case_id": case_id}, stream)
            stream.write("\n")
    except FileExistsError:
        return False
    return True


def main(args: list[str]) -> int:
    if len(args) != 3:
        return refuse("Usage: run_case.py CASE.json DATA_ROOT OUTPUT_ROOT")
    case_path, data_root, output_root = map(Path, args)
    if not case_path.is_file() or not ROUTES.is_file():
        return refuse("Missing case or reviewed route manifest.")
    try:
        case = json.loads(case_path.read_text())
        routes = json.loads(ROUTES.read_text())
    except (OSError, ValueError) as error:
        return refuse(f"Invalid case or route JSON: {error}")
    verdict = validate_case(case, routes)
    if verdict["status"] != "eligible":
        print(json.dumps(verdict), file=sys.stderr)
        return 78
    if not allocation_matches(case):
        return refuse("Slurm allocation does not match the one-case plan.")
    if case["backend"] != "cuda":
        return refuse("This worker accepts only reviewed CUDA cases.")
    if not RSCRIPT.is_file() or not R_WORKER.is_file() or \
            (case["dataset"] == "Deep1B 10M" and
             not DEEP1B_LOADER.is_file()):
        return refuse("Reviewed resident R worker is unavailable.")
    if not data_root.is_dir():
        return refuse("Resident dataset root is unavailable.")
    try:
        claimed = claim_allocation(output_root,
                                   allocation_identity(),
                                   case["case_id"])
    except OSError as error:
        return refuse(f"Cannot claim the Slurm allocation: {error}")
    if not claimed:
        return refuse("A case already claimed this Slurm allocation.")
    result_dir = output_root / case["case_id"]
    try:
        result_dir.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        return refuse("Case output already exists; refusing overwrite.")
    manifest = {
        "case_sha256": digest(case_path),
        "routes_sha256": digest(ROUTES),
        "worker_sha256": digest(R_WORKER),
        "deep1b_loader_sha256": digest(DEEP1B_LOADER)
        if case["dataset"] == "Deep1B 10M" else None,
        "slurm_job_id": os.environ["SLURM_JOB_ID"],
        "slurm_array_task_id": os.environ.get("SLURM_ARRAY_TASK_ID"),
        "status": "started",
    }
    (result_dir / "provenance.json").write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    command = [str(RSCRIPT), str(R_WORKER), str(case_path),
               str(data_root), str(result_dir)]
    worker_environment = {**os.environ,
                          "FASTEMBEDR_WORKER_DIR": str(HERE)}
    status = subprocess.run(command, check=False,
                            env=worker_environment).returncode
    manifest["status"] = "completed" if status == 0 else "failed"
    manifest["exit_code"] = status
    (result_dir / "provenance.json").write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
