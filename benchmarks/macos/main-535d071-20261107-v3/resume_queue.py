#!/usr/bin/env python3
"""Resume unattempted Mac cases while preserving the stopped v2 panel."""

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


STEFANO = Path("/Users/silvanopiazza/Documents/Stefano")
ROOT_NAME = "fastEmbedR-main-535d071-benchmark-v2-20261107"
PACKAGE_COMMIT = "535d071849945db3fa550d3c50f80633b91748cc"
RUNNER_SHA = "a81f4b2187eaf4911619d4cfb930ddd99477ac3a6231da6be187ed9c526f63d6"
WORKER_SHA = "9ec71d76dde7928891fff8cac95fc728dc2d2c50c806b95cafbacbbb865fb76d"
LIMITED_CASES = frozenset({
    "mass41_tsne_cpu1_d3_s4_r1_535d071_v2",
    "mass41_tsne_cpu4_d3_s4_r1_535d071_v2",
})


def swap_mib():
    result = subprocess.run(["sysctl", "vm.swapusage"], check=True,
                            capture_output=True, text=True, timeout=5)
    match = re.search(r"used = ([0-9.]+)([MG])", result.stdout)
    if not match:
        raise ValueError("Cannot measure system swap")
    return float(match.group(1)) * (1024 if match.group(2) == "G" else 1)


def record(path, **fields):
    with path.open("a") as stream:
        stream.write(json.dumps({"utc": time.strftime(
            "%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **fields},
            sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def case_state(root, case_id):
    output = root / "results" / case_id
    if not output.exists():
        return "pending"
    run = output / "run.json"
    if not run.is_file():
        return "ambiguous"
    data = json.loads(run.read_text())
    if (data.get("case_id") == case_id and
            data.get("status") == "completed" and
            data.get("cleanup_clear") is True and
            (output / "metrics.json").is_file()):
        return "completed"
    if (case_id in LIMITED_CASES and data.get("case_id") == case_id and
            data.get("timed_out") is True):
        return "resource_limited"
    return "ambiguous"


def plan(root):
    if root.name != ROOT_NAME or \
            not root.resolve().is_relative_to(STEFANO.resolve()):
        raise ValueError("Panel must stay inside Stefano")
    summary = json.loads((root / "plan-summary.json").read_text())
    if summary.get("cases") != 693 or summary.get("queued") != 693 or \
            summary.get("package_commit") != PACKAGE_COMMIT or \
            summary.get("storage_mode") != "resident" or \
            summary.get("fit_scope") != "full":
        raise ValueError("Source-locked v2 panel has changed")
    for name, expected in (("run_case.py", RUNNER_SHA),
                           ("worker.R", WORKER_SHA)):
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
            raise ValueError("Source-locked runner or worker has changed")
    names = (root / "queue.txt").read_text().splitlines()
    if len(names) != 693 or len(set(names)) != 693:
        raise ValueError("Queue is incomplete or duplicated")
    cases = []
    for name in names:
        if Path(name).name != name or not name.endswith(".json"):
            raise ValueError("Invalid case manifest name")
        manifest = root / "manifests" / name
        case = json.loads(manifest.read_text())
        if case["case_id"] != Path(name).stem or \
                Path(case["output_dir"]) != root / "results" / case["case_id"] or \
                case.get("source_sha256") != summary.get("source_sha256") or \
                case.get("dll_sha256") != summary.get("dll_sha256") or \
                case.get("storage_mode") != "resident" or \
                case.get("fit_scope") != "full" or \
                case.get("backend") not in ("cpu", "metal") or \
                case.get("spill") is not False:
            raise ValueError("Manifest output identity differs")
        cases.append((manifest, case["case_id"]))
    return cases


def run(root):
    cases = plan(root)
    log = root / "queue-status-v3.jsonl"
    lock = root / "resume-v3.lock"
    with lock.open("x") as stream:
        stream.write(str(os.getpid()) + "\n")
    baseline_swap = swap_mib()
    record(log, event="started", cases=len(cases), pid=os.getpid(),
           baseline_swap_mib=baseline_swap)
    for index, (manifest, case_id) in enumerate(cases, 1):
        state = case_state(root, case_id)
        if state in ("completed", "resource_limited"):
            record(log, event="preserved", index=index, case_id=case_id,
                   state=state)
            continue
        if state != "pending":
            record(log, event="stopped", index=index, case_id=case_id,
                   reason="ambiguous_prior_result")
            return 2
        if shutil.disk_usage(root).free < 100 * 1024 ** 3:
            record(log, event="stopped", index=index, reason="disk_floor")
            return 2
        current_swap = swap_mib()
        if current_swap - baseline_swap > 1024:
            record(log, event="stopped", index=index,
                   reason="swap_growth", swap_mib=current_swap)
            return 2
        record(log, event="case_started", index=index, case_id=case_id)
        with (root / "queue-worker-v3.log").open("a") as worker_log:
            status = subprocess.run(["/usr/bin/python3",
                str(root / "run_case.py"), str(manifest)], cwd=root,
                stdout=worker_log, stderr=subprocess.STDOUT,
                check=False).returncode
        state = case_state(root, case_id)
        record(log, event="case_finished", index=index, case_id=case_id,
               exit_code=status, state=state)
        if status or state != "completed":
            record(log, event="stopped", index=index, case_id=case_id,
                   reason="new_case_failed")
            return 2
    record(log, event="completed", cases=len(cases))
    return 0


def preflight(root):
    counts = Counter(case_state(root, case_id)
                     for _, case_id in plan(root))
    if counts["ambiguous"] or not 1 <= counts["resource_limited"] <= 2:
        raise ValueError("Panel has an unreviewed prior result")
    return dict(counts)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.dry_run:
            print(json.dumps(preflight(arguments.root), sort_keys=True))
            sys.exit(0)
        preflight(arguments.root)
        sys.exit(run(arguments.root))
    except Exception as error:
        print(repr(error), file=sys.stderr)
        sys.exit(2)
