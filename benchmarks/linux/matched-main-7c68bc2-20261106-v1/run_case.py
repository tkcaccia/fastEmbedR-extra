"""Run exactly one reviewed, resident fastEmbedR case in a Slurm allocation."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

from policy import DATA_FILES, validate_case


HERE = Path(__file__).resolve().parent
ROUTES = HERE / "routes.json"
R_WORKER = HERE / "matched_worker.R"
DEEP1B_LOADER = HERE / "deep1b_resident.R"
RSCRIPT = Path("/opt/r46/bin/Rscript")
CGROUP_ROOT = Path("/sys/fs/cgroup")
PACKAGE_COMMIT = "7c68bc2a48ff3f98d07f216db9601047951827fd"
IMAGE_MANIFEST = Path("/opt/fastembedr-manifest/source-identity.txt")


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


def verify_input_file(data_root: Path, case: dict) -> dict:
    """Hash resident input in a compute allocation before scientific work."""
    relative = DATA_FILES.get(case["dataset"])
    if relative is None:
        return {"status": "unsupported_dataset",
                "reason": "No reviewed resident input path."}
    path = data_root / relative
    try:
        contained = path.resolve().is_relative_to(data_root.resolve())
    except OSError:
        contained = False
    if not contained or not path.is_file():
        return {"status": "missing_input", "path": str(path)}
    started = time.monotonic()
    sha = hashlib.sha256()
    try:
        before = path.stat()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                sha.update(chunk)
        after = path.stat()
    except OSError as error:
        return {"status": "read_error", "path": str(path),
                "reason": str(error)}
    actual = sha.hexdigest()
    stable = (before.st_dev, before.st_ino, before.st_size,
              before.st_mtime_ns) == (after.st_dev, after.st_ino,
                                     after.st_size, after.st_mtime_ns)
    status = ("input_changed_during_check" if not stable else
              "verified" if actual == case["input_sha256"] else
              "input_mismatch")
    return {"status": status, "path": str(path),
            "expected_sha256": case["input_sha256"],
            "actual_sha256": actual,
            "size_bytes": after.st_size,
            "verification_seconds": time.monotonic() - started}


def job_cgroup_memory(proc_cgroup: Path = Path("/proc/self/cgroup"),
                      root: Path = CGROUP_ROOT,
                      environ: dict | None = None) -> dict | None:
    """Read a bounded Slurm job cgroup, never node-wide memory counters."""
    try:
        env = os.environ if environ is None else environ
        job_id = env["SLURM_JOB_ID"]
        requested_mib = int(env["SLURM_MEM_PER_NODE"])
        lines = proc_cgroup.read_text().splitlines()
        v2 = [line.split("::", 1)[1] for line in lines
              if line.startswith("0::")]
        if not job_id.isdecimal() or requested_mib < 1 or len(v2) != 1:
            return None
        relative = Path(v2[0].lstrip("/"))
        if (".." in relative.parts or
                f"job_{job_id}" not in relative.parts or
                "step_batch" not in relative.parts):
            return None
        folder = root / relative
        limit_text = (folder / "memory.max").read_text().strip()
        limit = None if limit_text == "max" else int(limit_text)
        peak = int((folder / "memory.peak").read_text().strip())
        current = int((folder / "memory.current").read_text().strip())
        if not (0 <= current <= peak and
                (limit is None or 0 < limit)):
            return None
        return {"path": str(folder), "job_id": job_id,
                "requested_bytes": requested_mib * 1024 * 1024,
                "limit_bytes": limit,
                "peak_bytes": peak, "current_bytes": current}
    except (KeyError, OSError, ValueError):
        return None


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
    if case["backend"] != "cpu":
        return refuse("CUDA route is not yet qualified or approved on HPC.")
    try:
        identity = IMAGE_MANIFEST.read_text().splitlines()
    except OSError:
        return refuse("Container source identity is missing.")
    if f"FastEmbedRCommit={PACKAGE_COMMIT}" not in identity:
        return refuse("Container package source differs from the cohort.")
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
        "package_commit": PACKAGE_COMMIT,
        "status": "started",
    }
    (result_dir / "provenance.json").write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    input_check = verify_input_file(data_root, case)
    (result_dir / "input_identity.json").write_text(
        json.dumps(input_check, sort_keys=True, indent=2) + "\n")
    if input_check["status"] != "verified":
        manifest["status"] = input_check["status"]
        manifest["exit_code"] = 78
        (result_dir / "provenance.json").write_text(
            json.dumps(manifest, sort_keys=True, indent=2) + "\n")
        return 78
    command = [str(RSCRIPT), str(R_WORKER), str(case_path),
               str(data_root), str(result_dir)]
    worker_environment = {**os.environ,
                          "FASTEMBEDR_WORKER_DIR": str(HERE)}
    memory_before = job_cgroup_memory()
    status = subprocess.run(command, check=False,
                            env=worker_environment).returncode
    memory_after = job_cgroup_memory()
    child_peak_bytes = resource.getrusage(
        resource.RUSAGE_CHILDREN).ru_maxrss * 1024
    memory_verified = (memory_before is not None and
                       memory_after is not None and
                       memory_before["path"] == memory_after["path"] and
                       memory_after["peak_bytes"] >=
                       memory_before["peak_bytes"])
    (result_dir / "memory.json").write_text(json.dumps({
        "scope": "slurm_job_cgroup" if memory_verified else
                 "unverified",
        "before": memory_before,
        "after": memory_after,
        "peak_ram_bytes": memory_after["peak_bytes"]
        if memory_verified else None,
        "child_process_peak_bytes": child_peak_bytes,
    }, sort_keys=True, indent=2) + "\n")
    manifest["status"] = ("completed" if status == 0 and memory_verified
                          else "memory_unverified" if status == 0 else
                          "failed")
    manifest["exit_code"] = status if status != 0 else (
        0 if memory_verified else 79)
    (result_dir / "provenance.json").write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    return manifest["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
