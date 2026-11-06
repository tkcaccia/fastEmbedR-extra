#!/usr/bin/env python3
"""Read-only completeness and provenance audit of a Mac resident panel."""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re


def read_json(path):
    return json.loads(path.read_text())


def finite(value, low=None, high=None):
    if type(value) not in (int, float) or not math.isfinite(value):
        return False
    return (low is None or value >= low) and (
        high is None or value <= high)


def quality_ok(method, quality):
    if not isinstance(quality, dict):
        return False
    if method in ("t-SNE", "UMAP"):
        return all(finite(quality.get(key), 0, 1) for key in
                   ("trustworthiness", "label_accuracy"))
    if method in ("Leiden", "Louvain"):
        return (finite(quality.get("ari"), -1, 1) and
                finite(quality.get("modularity"), -1, 1) and
                type(quality.get("communities")) is int and
                quality["communities"] > 0)
    values = quality.get("singular_values")
    return (method == "PCA" and isinstance(values, list) and
            bool(values) and all(finite(value, 0) for value in values))


def used_swap_mib(value):
    if not isinstance(value, str):
        return None
    match = re.search(r"used = ([0-9.]+)([MG])", value)
    if not match:
        return None
    amount = float(match.group(1))
    return amount * (1024 if match.group(2) == "G" else 1)


def identity_ok(case, raw, run, provenance, code_hashes):
    expected = {"case_sha256": hashlib.sha256(raw).hexdigest(),
                "source_sha256": case["source_sha256"],
                "dll_sha256": case["dll_sha256"],
                "input_sha256": case["input_sha256"],
                **code_hashes}
    return all(run.get(key) == value and
               provenance.get(key) == value
               for key, value in expected.items())


def check_completed(case, raw, output, code_hashes):
    problems = []
    run = read_json(output / "run.json")
    metrics = read_json(output / "metrics.json")
    provenance = read_json(output / "provenance.json")
    if not identity_ok(case, raw, run, provenance, code_hashes):
        problems.append("source_or_input_identity")
    if (run.get("case_id") != case["case_id"] or
            run.get("status") != "completed" or
            run.get("exit_code") != 0 or
            run.get("timed_out") is not False or
            run.get("cleanup_clear") is not True or
            not finite(run.get("peak_rss_bytes"), 1)):
        problems.append("run_or_cleanup")
    before = used_swap_mib(run.get("swap_before"))
    after = used_swap_mib(run.get("swap_after"))
    if before is None or after is None or after - before > 1024:
        problems.append("swap_measurement")
    keys = ("case_id", "dataset", "method", "backend", "seed",
            "repetition", "dimensions")
    if any(metrics.get(key) != case.get(key) for key in keys):
        problems.append("case_or_method_identity")
    if (metrics.get("storage_mode") != "resident" or
            metrics.get("fit_scope") != "full" or
            metrics.get("n_rows") != case["expected_rows"] or
            metrics.get("n_columns") != case["expected_columns"]):
        problems.append("fit_scope_or_shape")
    observed = metrics.get("observed_backend")
    if not isinstance(observed, str) or not observed.startswith(
            case["backend"]):
        problems.append("backend_fallback")
    if not quality_ok(case["method"], metrics.get("quality")):
        problems.append("quality_missing_or_invalid")
    for stage in ("load_seconds", "preprocess_seconds", "graph_seconds",
                  "fit_seconds", "quality_seconds"):
        if not finite(metrics.get(stage), 0):
            problems.append("invalid_" + stage)
    if not (output / "output.rds").is_file() or not (
            output / "output.rds").stat().st_size > 0:
        problems.append("output_missing")
    return problems


def audit(root):
    plan = read_json(root / "plan-summary.json")
    manifests = sorted((root / "manifests").glob("*.json"))
    queued = (root / "queue.txt").read_text().splitlines()
    events = [json.loads(line) for line in
              (root / "queue-status.jsonl").read_text().splitlines()
              if line.strip()]
    finished = {event["case_id"]: event for event in events
                if event.get("event") == "case_finished"}
    queued_ids = {Path(name).stem for name in queued}
    code_hashes = {name + "_sha256": hashlib.sha256(
        (root / file).read_bytes()).hexdigest()
        for name, file in (("worker", "worker.R"),
                           ("runner", "run_case.py"))}
    terminal = [event for event in events if event.get("event") in
                ("completed", "stopped", "failed")]
    queue_done = bool(terminal and terminal[-1]["event"] == "completed")
    problems = []
    counts = Counter()
    seen = set()
    for manifest in manifests:
        raw = manifest.read_bytes()
        case = json.loads(raw)
        case_id = case["case_id"]
        if case_id in seen:
            problems.append({"case_id": case_id, "issue": "duplicate_id"})
        seen.add(case_id)
        output = root / "results" / case_id
        if Path(case["output_dir"]) != output:
            problems.append({"case_id": case_id,
                             "issue": "output_path_mismatch"})
        if not (output / "run.json").is_file():
            counts["in_progress" if output.exists() else "pending"] += 1
            continue
        try:
            issues = check_completed(case, raw, output, code_hashes)
        except (OSError, ValueError, KeyError, TypeError) as error:
            issues = ["unreadable_result:" + type(error).__name__]
        if case_id in queued_ids:
            event = finished.get(case_id)
            if ((not event and queue_done) or
                    (event and (event.get("exit_code") != 0 or
                                event.get("cleanup_clear") is not True))):
                issues.append("queue_failure")
        counts["failed" if issues else "completed"] += 1
        problems.extend({"case_id": case_id, "issue": issue}
                        for issue in issues)
    if len(manifests) != plan["cases"] or len(queued) != plan["queued"]:
        problems.append({"case_id": None, "issue": "plan_count_mismatch"})
    if len(terminal) > 1 or (terminal and terminal[-1]["event"] !=
                             "completed"):
        problems.append({"case_id": None, "issue": "queue_terminal_failure"})
    complete = (counts["completed"] == plan["cases"] and
                queue_done and not problems)
    return {"status": "passed" if complete else
            "failed" if problems else "incomplete",
            "planned": plan["cases"], "counts": dict(counts),
            "problems": problems[:100]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("panel_root", type=Path)
    args = parser.parse_args()
    report = audit(args.panel_root)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
