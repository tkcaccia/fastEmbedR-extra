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


def sample(root, group):
    result = subprocess.run(
        ["nvidia-smi", "--query-compute-apps=gpu_uuid,pid,used_gpu_memory",
         "--format=csv,noheader,nounits"],
        capture_output=True, text=True, timeout=10, check=True)
    devices = {}
    matched = False
    for line in result.stdout.splitlines():
        parts = [part.strip() for part in line.split(",")]
        if len(parts) != 3:
            continue
        try:
            uuid, pid, mib = parts[0], int(parts[1]), int(parts[2])
        except ValueError:
            continue
        if belongs_to(pid, root, group):
            devices[uuid] = devices.get(uuid, 0) + mib * 1024 * 1024
            matched = True
    return sum(devices.values()), matched, devices


def monitor(pid, output):
    group = os.getpgid(pid)
    peak = 0
    samples = 0
    matched = 0
    errors = 0
    device_peaks = {}
    while Path(f"/proc/{pid}").exists():
        try:
            used, found, devices = sample(pid, group)
            peak = max(peak, used)
            matched += int(found)
            samples += 1
            for uuid, bytes_used in devices.items():
                device_peaks[uuid] = max(device_peaks.get(uuid, 0),
                                         bytes_used)
        except (OSError, subprocess.SubprocessError):
            errors += 1
        time.sleep(0.25)
    with output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, ("peak_bytes", "samples",
            "matched_samples", "errors", "device_count",
            "peak_device_bytes", "peak_per_device_json",
            "attribution", "status"))
        writer.writeheader()
        writer.writerow(dict(peak_bytes=peak, samples=samples,
            matched_samples=matched, errors=errors,
            device_count=len(device_peaks),
            peak_device_bytes=max(device_peaks.values(), default=0),
            peak_per_device_json=json.dumps(device_peaks, sort_keys=True),
            attribution="process_tree_or_process_group",
            status="ok" if peak > 0 else "unavailable"))


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
        monitor(int(sys.argv[1]), Path(sys.argv[2]))
