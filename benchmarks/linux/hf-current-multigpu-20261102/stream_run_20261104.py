"""Two-A10G qualification for bounded CUDA graph clustering."""

import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

import numpy as np


WORKER = Path(__file__).with_name("massive_cuda_stream_cluster.py")


def live_group(pgid):
    members = []
    for path in Path("/proc").glob("[0-9]*/stat"):
        try:
            fields = path.read_text().rsplit(")", 1)[1].split()
        except (FileNotFoundError, PermissionError, IndexError):
            continue
        if fields[0] != "Z" and int(fields[2]) == pgid:
            members.append(int(path.parent.name))
    return members


def stop_group(pgid):
    for action in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pgid, action)
        except ProcessLookupError:
            return
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if not live_group(pgid):
                return
            time.sleep(1)
    if live_group(pgid):
        raise RuntimeError("GPU worker process group did not stop")


def run_owned(command, timeout):
    job = subprocess.Popen(command, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True,
                           start_new_session=True)
    try:
        stdout, stderr = job.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        stop_group(job.pid)
        job.communicate(timeout=10)
        raise RuntimeError("GPU worker exceeded its case deadline") from error
    except BaseException:
        stop_group(job.pid)
        job.communicate(timeout=10)
        raise
    if job.returncode or live_group(job.pid):
        stop_group(job.pid)
        raise RuntimeError(stderr[-10000:] or
                           "GPU worker left a live descendant")
    return stdout


def write_graph(root, rows, degree):
    group = rows // 4
    if degree % 2 or group <= degree:
        raise ValueError("Invalid ring fixture")
    offsets = np.arange(rows + 1, dtype="<u8") * degree
    shifts = np.r_[np.arange(1, degree // 2 + 1),
                   -np.arange(1, degree // 2 + 1)]
    vertices = np.arange(rows, dtype=np.int64)
    neighbors = ((vertices[:, None] % group + shifts[None, :]) %
                 group + (vertices[:, None] // group) * group + 1)
    paths = [root / "offsets.u64", root / "indices.u32",
             root / "weights.f32"]
    offsets.tofile(paths[0])
    neighbors.astype("<u4").tofile(paths[1])
    np.ones(rows * degree, dtype="<f4").tofile(paths[2])
    return paths


def independent_modularity(paths, labels, degree):
    target = np.memmap(paths[1], dtype="<u4", mode="r") - 1
    source = np.repeat(np.arange(len(labels), dtype=np.int32), degree)
    internal = np.count_nonzero(labels[source] == labels[target])
    volumes = np.bincount(labels - 1, minlength=len(labels)) * degree
    total = len(target)
    return internal / total - np.sum((volumes / total)**2)


def execute(root, rows, degree, pool_bytes, passes, timeout,
            initial=False):
    root.mkdir()
    paths = write_graph(root, rows, degree)
    output = root / "labels.u32"
    metadata = root / "metadata.json"
    command = [sys.executable, str(WORKER), "--paths",
        *(str(path) for path in paths), "--vertices", str(rows),
        "--devices", "2", "--chunk-rows", "2048",
        "--edge-budget", "65536", "--passes", str(passes),
        "--resolution", "1", "--seed", "1",
        "--gpu-pool-bytes", str(pool_bytes),
        "--output", str(output), "--metadata", str(metadata)]
    if initial:
        if rows != 12:
            raise ValueError("Initial-map fixture needs twelve rows")
        initial_path = root / "initial.u32"
        np.repeat(np.arange(1, 5, dtype="<u4"), 3).tofile(
            initial_path)
        command += ["--initial", str(initial_path),
                    "--initial-count", "4"]
    run_owned(command, timeout)
    labels = np.fromfile(str(output) + ".part", dtype="<u4")
    report = json.loads(metadata.read_text())
    if len(labels) != rows or report["gpu_devices_used"] != [0, 1]:
        raise RuntimeError("Two-GPU output is incomplete")
    if len(set(report["gpu_pci_bus_ids"])) != 2:
        raise RuntimeError("GPU workers used the same physical GPU")
    if report["initial_partition"] is not initial:
        raise RuntimeError("Initial-map use was not reported")
    if pool_bytes:
        combined = 2 * pool_bytes
        if report["graph_file_bytes"] <= combined:
            raise RuntimeError("Graph does not exceed test GPU pool")
        if any(value > pool_bytes for value in
               report["peak_gpu_pool_bytes"].values()):
            raise RuntimeError("GPU memory pool exceeded limit")
    independent = independent_modularity(paths, labels, degree)
    if abs(independent - report["modularity"]) > 1e-5:
        raise RuntimeError("Independent modularity audit failed")
    if rows == 12 and labels.tolist() != [1, 1, 1, 2, 2, 2,
                                          3, 3, 3, 4, 4, 4]:
        raise RuntimeError("Small graph partition is incorrect")
    return {"rows": rows, "degree": degree,
            "graph_file_bytes": report["graph_file_bytes"],
            "gpu_pool_limit_bytes_each": pool_bytes,
            "peak_gpu_pool_bytes": report["peak_gpu_pool_bytes"],
            "gpu_devices_used": report["gpu_devices_used"],
            "gpu_pci_bus_ids": report["gpu_pci_bus_ids"],
            "modularity": report["modularity"],
            "independent_modularity": independent,
            "communities": report["communities"],
            "moves": report["moves"],
            "initial_partition": report["initial_partition"]}


def main():
    devices = subprocess.run(["nvidia-smi", "--query-gpu=uuid,name,"
        "memory.total", "--format=csv,noheader,nounits"],
        check=True, capture_output=True, text=True).stdout.strip()
    if len(devices.splitlines()) != 2:
        raise RuntimeError("Expected exactly two visible GPUs")
    uuids = [line.split(",", 1)[0].strip()
             for line in devices.splitlines()]
    if any(not uuid.startswith("GPU-") for uuid in uuids):
        raise RuntimeError("GPU UUIDs are unavailable")
    os.environ["CUDA_VISIBLE_DEVICES"] = ",".join(uuids)
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        small = execute(root / "small", 12, 2, 0, 2, 60)
        small_initial = execute(root / "small-initial", 12, 2,
                                0, 2, 60, initial=True)
        bounded = execute(root / "bounded", 100000, 32,
                          8 * 1024**2, 1, 360)
    print(json.dumps({"worker_sha256": hashlib.sha256(
        WORKER.read_bytes()).hexdigest(), "devices": devices,
        "small": small, "small_initial": small_initial,
        "bounded": bounded}, indent=2))


if __name__ == "__main__":
    main()
