#!/usr/bin/env python3
"""Sample GPU memory attributed to a fit tree or process group."""

import csv
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path


def parent_of(pid):
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("PPid:"):
                return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return 0


def belongs_to(pid, root, group):
    candidate = pid
    for _ in range(32):
        if pid == root:
            return True
        pid = parent_of(pid)
        if pid < 2:
            break
    try:
        return group is not None and os.getpgid(candidate) == group
    except (OSError, ValueError):
        return False


def process_running(pid):
    try:
        status = Path(f"/proc/{pid}/stat").read_text()
    except FileNotFoundError:
        return False
    state = status.rsplit(") ", 1)[1].split()[0]
    return state not in ("Z", "X")


def query_gpu_processes(timeout):
    command = ["nvidia-smi",
        "--query-compute-apps=gpu_uuid,pid,used_gpu_memory",
        "--format=csv,noheader,nounits"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True,
                               start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        try:
            process.kill()
        except OSError:
            pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired as pending:
            raise RuntimeError(
                f"nvidia-smi PID {process.pid} did not stop") from pending
        raise exc
    if process.returncode != 0:
        raise subprocess.CalledProcessError(
            process.returncode, command, stdout, stderr)
    return stdout


def sample(root, group, known_pids=(), timeout=10):
    devices = {}
    owned_pids = set()
    for line in query_gpu_processes(timeout).splitlines():
        parts = [part.strip() for part in line.split(",")]
        if len(parts) != 3:
            raise ValueError("Malformed GPU process telemetry")
        try:
            uuid, pid = parts[0], int(parts[1])
        except ValueError as exc:
            raise ValueError("Malformed GPU process telemetry") from exc
        if not uuid:
            raise ValueError("Missing GPU UUID in telemetry")
        if not (pid in known_pids or belongs_to(pid, root, group)):
            continue
        try:
            mib = int(parts[2])
        except ValueError as exc:
            raise ValueError("Missing owned GPU memory telemetry") from exc
        owned_pids.add(pid)
        devices[uuid] = devices.get(uuid, 0) + mib * 1024 * 1024
    return sum(devices.values()), bool(owned_pids), devices, owned_pids


def wait_for_release(root, group, known_pids):
    empty = 0
    for check in range(8):
        try:
            _, found, _, pids = sample(root, group, known_pids, timeout=3)
        except (OSError, RuntimeError, ValueError,
                subprocess.SubprocessError):
            return "unknown", check + 1
        known_pids.update(pids)
        empty = 0 if found else empty + 1
        if empty == 2:
            return "observed_clear", check + 1
        if check < 7:
            time.sleep(1.0)
    return "contexts_remain", 8


def monitor(pid, output):
    try:
        group = os.getpgid(pid)
    except ProcessLookupError:
        group = None
    peak = 0
    samples = 0
    matched = 0
    errors = 0
    device_peaks = {}
    owned_pids = set()
    while process_running(pid):
        try:
            used, found, devices, pids = sample(pid, group, owned_pids)
            owned_pids.update(pids)
            peak = max(peak, used)
            matched += int(found)
            samples += 1
            for uuid, bytes_used in devices.items():
                device_peaks[uuid] = max(device_peaks.get(uuid, 0),
                                         bytes_used)
        except (OSError, RuntimeError, ValueError,
                subprocess.SubprocessError):
            errors += 1
            break
        time.sleep(1.0)
    cleanup = "unknown"
    cleanup_checks = 0
    if samples and not errors:
        cleanup, cleanup_checks = wait_for_release(
            pid, group, owned_pids)
        if cleanup == "unknown":
            errors += 1
    valid = (peak > 0 and matched >= 2 and errors == 0 and
             cleanup == "observed_clear")
    with output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, ("peak_bytes", "samples",
            "matched_samples", "errors", "device_count",
            "peak_device_bytes", "peak_per_device_json",
            "attribution", "cleanup_status", "cleanup_checks",
            "owned_pid_count", "status"))
        writer.writeheader()
        writer.writerow(dict(peak_bytes=peak, samples=samples,
            matched_samples=matched, errors=errors,
            device_count=len(device_peaks),
            peak_device_bytes=max(device_peaks.values(), default=0),
            peak_per_device_json=json.dumps(device_peaks, sort_keys=True),
            attribution="process_tree_or_process_group",
            cleanup_status=cleanup, cleanup_checks=cleanup_checks,
            owned_pid_count=len(owned_pids),
            status="ok" if valid else "unavailable"))
    return 0 if valid else 1


def verify_devices(memory_path, map_path):
    with memory_path.open(newline="") as stream:
        memory = next(csv.DictReader(stream))
    with map_path.open(newline="") as stream:
        mapping = list(csv.DictReader(stream))
    requested = {row["uuid"].strip().upper() for row in mapping}
    peaks = json.loads(memory["peak_per_device_json"])
    observed = {uuid.strip().upper() for uuid in peaks}
    if (memory["status"] != "ok" or not requested or
            len(requested) != len(mapping) or
            len(observed) != len(peaks) or observed != requested or
            any(isinstance(value, bool) or
                not isinstance(value, (int, float)) or
                not math.isfinite(value) or value <= 0
                for value in peaks.values())):
        raise ValueError("GPU memory sampling did not observe "
                         "the requested device UUIDs")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--verify":
        verify_devices(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        raise SystemExit(monitor(int(sys.argv[1]), Path(sys.argv[2])))
