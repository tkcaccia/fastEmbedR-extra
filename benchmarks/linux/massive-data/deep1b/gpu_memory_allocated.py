#!/usr/bin/env python3
"""Measure device-wide memory on both Slurm-allocated GPUs during a fit."""

import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path


MIB = 1024 * 1024


def allocated_indices(environment):
    value = environment.get("SLURM_JOB_GPUS", "")
    parts = value.split(",")
    if len(parts) != 2 or any(not part.isdigit() for part in parts):
        raise ValueError("SLURM_JOB_GPUS must identify two GPU indices")
    indices = tuple(int(part) for part in parts)
    if len(set(indices)) != 2:
        raise ValueError("SLURM_JOB_GPUS contains a duplicate GPU")
    return indices


def device_memory():
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=index,uuid,memory.used",
         "--format=csv,noheader,nounits"],
        capture_output=True, text=True, timeout=10, check=True)
    devices = {}
    for row in csv.reader(result.stdout.splitlines()):
        if len(row) != 3:
            continue
        index, uuid, used = (item.strip() for item in row)
        devices[int(index)] = (uuid, int(used) * MIB)
    return devices


def visible_devices(root, indices, baseline):
    manifest = json.loads((root / "hardware_manifest.json").read_text())
    visible = {}
    for device in manifest["devices"]:
        if device.get("backend") != "cuda" or not device.get(
                "process_visible"):
            continue
        logical = device.get("logical_id")
        physical = device.get("physical_id")
        uuid = device.get("uuid")
        if logical is None or physical is None or not uuid:
            raise ValueError("Visible GPU lacks a complete identity")
        if logical in visible:
            raise ValueError("Duplicate CUDA-visible GPU ID")
        visible[logical] = (physical, uuid)
    if set(visible) != {0, 1}:
        raise ValueError("Expected exactly two CUDA-visible GPUs")
    for physical, uuid in visible.values():
        if physical not in indices or physical not in baseline or \
                baseline[physical][0].lower() != uuid.lower():
            raise ValueError("GPU manifest and Slurm allocation disagree")
    return visible


def record(root, devices, baseline, peaks, samples, errors, fit_code):
    rows = []
    for logical, (physical, uuid) in sorted(devices.items()):
        _, start = baseline[physical]
        rows.append(dict(logical_id=logical, physical_id=physical,
            uuid=uuid, baseline_bytes=start,
            peak_bytes=peaks[physical],
            delta_bytes=max(0, peaks[physical] - start)))
    with (root / "gpu_memory.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    active = sum(row["delta_bytes"] >= MIB for row in rows)
    summary = dict(status="two_devices_active" if active == 2 else
        "incomplete_device_evidence",
        memory_scope="device_wide_sampled",
        allocated_devices=[row["physical_id"] for row in rows],
        active_devices=active, samples=samples, errors=errors,
        fit_exit_code=fit_code)
    (root / "gpu_summary.json").write_text(
        json.dumps(summary, sort_keys=True) + "\n")


def run(root, command):
    indices = allocated_indices(os.environ)
    baseline = device_memory()
    devices = visible_devices(root, indices, baseline)
    peaks = {index: baseline[index][1] for index in indices}
    samples = errors = 0
    with (root / "fit.out").open("w") as stdout, \
            (root / "fit.err").open("w") as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr)
        while process.poll() is None:
            try:
                current = device_memory()
                for index in indices:
                    if (index not in current or
                            current[index][0] != baseline[index][0]):
                        raise ValueError("Allocated GPU identity changed")
                    peaks[index] = max(peaks[index], current[index][1])
                samples += 1
            except (OSError, ValueError, subprocess.SubprocessError):
                errors += 1
            time.sleep(0.1)
        fit_code = process.wait()
    record(root, devices, baseline, peaks, samples, errors, fit_code)
    return fit_code


if __name__ == "__main__":
    marker = sys.argv.index("--")
    directory = Path(sys.argv[1])
    try:
        sys.exit(run(directory, sys.argv[marker + 1:]))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        (directory / "gpu_monitor_error.txt").write_text(str(error) + "\n")
        raise
