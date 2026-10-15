#!/usr/bin/env python3
"""Sample campaign payload space while a full-graph fit runs."""

import csv
import os
import sys
import time
from pathlib import Path


def payload_bytes(root):
    apparent = allocated = 0
    for name in ("work", "results"):
        directory = root / name
        if not directory.is_dir():
            continue
        for parent, _, files in os.walk(directory):
            for filename in files:
                try:
                    info = os.stat(Path(parent) / filename,
                                   follow_symlinks=False)
                except FileNotFoundError:
                    continue
                apparent += info.st_size
                allocated += info.st_blocks * 512
    return apparent, allocated


def monitor(pid, root, output):
    peak_apparent = peak_allocated = samples = 0
    while True:
        apparent, allocated = payload_bytes(root)
        peak_apparent = max(peak_apparent, apparent)
        peak_allocated = max(peak_allocated, allocated)
        samples += 1
        if not Path(f"/proc/{pid}").exists():
            break
        time.sleep(1)
    with output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, ("peak_apparent_bytes",
            "peak_allocated_bytes", "samples", "scope"))
        writer.writeheader()
        writer.writerow(dict(peak_apparent_bytes=peak_apparent,
            peak_allocated_bytes=peak_allocated, samples=samples,
            scope="fit_work_and_results"))


if __name__ == "__main__":
    monitor(int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
