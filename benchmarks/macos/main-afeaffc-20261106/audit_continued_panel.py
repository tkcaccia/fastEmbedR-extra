#!/usr/bin/env python3
"""Read-only audit across the original Mac queue and versioned continuations."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from audit_panel import check_completed, identity_ok, read_json


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def events(path):
    return [json.loads(line) for line in path.read_text().splitlines()
            if line.strip()]


def audit(root, continuations):
    queue = (root / "queue.txt").read_text().splitlines()
    manifest_paths = sorted((root / "manifests").glob("*.json"))
    plan = read_json(root / "plan-summary.json")
    problems = []
    if (len(manifest_paths) != plan["cases"] or
            len(queue) != plan["queued"] or
            len(set(queue)) != len(queue)):
        problems.append({"case_id": None, "issue": "plan_or_queue_count"})
    manifest_names = {path.name for path in manifest_paths}
    if any(name not in manifest_names for name in queue):
        problems.append({"case_id": None, "issue": "queue_manifest_missing"})
    queue_ids = [Path(name).stem for name in queue]
    queue_position = {case_id: i + 1 for i, case_id in
                      enumerate(queue_ids)}
    queue_hash = digest(root / "queue.txt")
    code_hashes = {name + "_sha256": digest(root / file)
                   for name, file in (("worker", "worker.R"),
                                      ("runner", "run_case.py"))}
    all_logs = [events(root / "queue-status.jsonl")]
    controller_status = []
    for directory in continuations:
        history = events(directory / "resume-status.jsonl")
        if not history or history[0].get("event") != "started":
            problems.append({"case_id": None,
                             "issue": "continuation_missing_start"})
            continue
        start = history[0]
        controller = directory / ("resume_panel_v2.py"
            if "v2" in directory.name else "resume_panel_v1.py")
        if (not controller.is_file() or
                start.get("controller_sha256") != digest(controller) or
                start.get("queue_sha256") != queue_hash):
            problems.append({"case_id": None,
                             "issue": "continuation_identity"})
        all_logs.append(history)
        controller_status.append(history[-1].get("event"))
    latest = {}
    for log in all_logs:
        for event in log:
            if event.get("event") not in (
                    "case_started", "case_finished", "deferred"):
                continue
            case_id = event.get("case_id")
            if queue_position.get(case_id) != event.get("index"):
                problems.append({"case_id": case_id,
                                 "issue": "event_queue_mismatch"})
            latest[case_id] = event
    counts = Counter()
    completed = []
    failed = []
    deferred = []
    seen = set()
    for path in manifest_paths:
        raw = path.read_bytes()
        case = json.loads(raw)
        case_id = case["case_id"]
        if case_id in seen:
            problems.append({"case_id": case_id, "issue": "duplicate_id"})
        seen.add(case_id)
        output = root / "results" / case_id
        event = latest.get(case_id, {})
        if Path(case["output_dir"]) != output:
            problems.append({"case_id": case_id,
                             "issue": "output_path_mismatch"})
        run_path = output / "run.json"
        if run_path.is_file():
            try:
                run = read_json(run_path)
                provenance = read_json(output / "provenance.json")
                if not identity_ok(case, raw, run, provenance,
                                   code_hashes):
                    problems.append({"case_id": case_id,
                                     "issue": "result_identity"})
                if (run.get("status") == "completed" and
                        run.get("exit_code") == 0):
                    issues = check_completed(case, raw, output,
                                             code_hashes)
                    if case_id in queue_position and (
                            event.get("event") != "case_finished" or
                            event.get("status") != "completed"):
                        issues.append("missing_success_event")
                    problems.extend({"case_id": case_id, "issue": issue}
                                    for issue in issues)
                    if issues:
                        counts["invalid_result"] += 1
                    else:
                        counts["completed"] += 1
                        completed.append(case_id)
                else:
                    if case_id in queue_position and (
                            event.get("event") != "case_finished" or
                            event.get("status") != "failed"):
                        problems.append({"case_id": case_id,
                                         "issue": "missing_failure_event"})
                    counts["failed"] += 1
                    failed.append({"case_id": case_id,
                                   "exit_code": run.get("exit_code"),
                                   "timed_out": run.get("timed_out"),
                                   "cleanup_clear":
                                   run.get("cleanup_clear")})
            except (OSError, ValueError, KeyError, TypeError) as error:
                counts["invalid_result"] += 1
                problems.append({"case_id": case_id,
                                 "issue": "unreadable_result:" +
                                 type(error).__name__})
        elif event.get("event") == "deferred":
            counts["deferred"] += 1
            deferred.append(case_id)
        elif event.get("event") == "case_started" or output.exists():
            counts["running"] += 1
        else:
            counts["pending"] += 1
    if sum(counts.values()) != len(manifest_paths):
        problems.append({"case_id": None, "issue": "classification_count"})
    if problems:
        status = "audit_failed"
    elif counts["pending"] or counts["running"]:
        status = "in_progress"
    elif counts["failed"] or counts["deferred"]:
        status = "finished_with_failures"
    else:
        status = "passed"
    return {"status": status, "planned": len(manifest_paths),
            "counts": dict(counts), "failed": failed,
            "deferred": deferred, "problems": problems[:100],
            "controller_status": controller_status}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("panel_root", type=Path)
    parser.add_argument("continuations", type=Path, nargs="*")
    args = parser.parse_args()
    print(json.dumps(audit(args.panel_root, args.continuations),
                     indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
