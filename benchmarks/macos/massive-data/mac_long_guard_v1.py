#!/usr/bin/env python3
"""Bound one long Mac worker by time, free memory, and new swap activity."""

import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path


def command_output(*command):
    return subprocess.run(
        command, capture_output=True, text=True, check=True, timeout=5
    ).stdout


def mac_state():
    free_text = command_output("memory_pressure", "-Q")
    match = re.search(
        r"System-wide[^\n]*free[^\n]*percentage:\s*([0-9.]+)%",
        free_text,
    )
    if not match:
        raise ValueError("Mac free-memory percentage is unavailable")
    vm_text = command_output("vm_stat")
    counters = {}
    for label in ("Pageouts", "Swapouts"):
        found = re.search(rf"^{label}:\s*([0-9]+)\.", vm_text, re.M)
        if not found:
            raise ValueError(f"Mac {label} counter is unavailable")
        counters[label.lower()] = int(found.group(1))
    return float(match.group(1)), counters


def memory_gate_failed(free_pct, baseline, current):
    return free_pct < 50 or current["swapouts"] > baseline["swapouts"]


def write_evidence(path, record):
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(record, sort_keys=True, indent=2) + "\n")
    os.replace(temp, path)


def group_alive(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False


def signal_group(pid, action):
    try:
        os.killpg(pid, action)
    except ProcessLookupError:
        pass


def stop_group(process):
    if group_alive(process.pid):
        signal_group(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    if group_alive(process.pid):
        signal_group(process.pid, signal.SIGKILL)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    until = time.monotonic() + 5
    while group_alive(process.pid) and time.monotonic() < until:
        time.sleep(0.1)
    return not group_alive(process.pid)


def main():
    if len(sys.argv) < 4:
        raise SystemExit(
            "usage: mac_memory_guard_v1.py SECONDS EVIDENCE COMMAND..."
        )
    seconds = float(sys.argv[1])
    if not 0 < seconds <= 45 * 86400:
        raise ValueError("Deadline must be in (0, 45 days] seconds")
    evidence = Path(sys.argv[2])
    record = {
        "status": "not_started",
        "command": sys.argv[3:],
        "minimum_free_pct": 50,
        "deadline_seconds": seconds,
    }
    try:
        baseline_free, baseline = mac_state()
        record.update(baseline_free_pct=baseline_free, baseline=baseline)
        if baseline_free < 50:
            raise ValueError("Free memory is below 50% before worker start")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        record.update(status="preflight_failed", reason=str(error))
        write_evidence(evidence, record)
        print(record["reason"], file=sys.stderr)
        return 125
    try:
        process = subprocess.Popen(sys.argv[3:], start_new_session=True)
    except OSError as error:
        record.update(status="launch_failed", reason=str(error))
        write_evidence(evidence, record)
        print(record["reason"], file=sys.stderr)
        return 125
    started = time.monotonic()
    interrupted = False

    def interrupt(_signum, _frame):
        nonlocal interrupted
        interrupted = True

    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    status = "passed"
    reason = ""
    free_min = baseline_free
    final = baseline
    while True:
        if interrupted:
            status, reason = "interrupted", "Guard received a stop signal"
            break
        if time.monotonic() - started >= seconds:
            status, reason = "deadline", "Worker exceeded its deadline"
            break
        try:
            free, final = mac_state()
            free_min = min(free_min, free)
            if memory_gate_failed(free, baseline, final):
                status = "memory_gate"
                reason = "Free memory fell below 50% or swapouts rose"
                break
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            status, reason = "measurement_failed", str(error)
            break
        if process.poll() is not None:
            break
        time.sleep(10)
    exit_code = process.poll()
    if status != "passed" or exit_code is None or group_alive(process.pid):
        cleaned = stop_group(process)
        if status == "passed" and not cleaned:
            status, reason = "cleanup_failed", "Worker group remains live"
        elif status == "passed" and exit_code is not None:
            status, reason = "orphaned_child", "Worker left a child process"
    exit_code = process.poll()
    if status == "passed" and exit_code != 0:
        status = "worker_failed"
        reason = f"Worker exited with status {exit_code}"
    record.update(
        status=status,
        reason=reason,
        worker_exit_code=exit_code,
        free_pct_min=free_min,
        final=final,
        elapsed_seconds=time.monotonic() - started,
    )
    write_evidence(evidence, record)
    if status != "passed":
        print(reason, file=sys.stderr)
    return 0 if status == "passed" else (124 if status == "deadline" else 125)


if __name__ == "__main__":
    raise SystemExit(main())
