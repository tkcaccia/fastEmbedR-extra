#!/usr/bin/env python3
"""Submit independent Deep1B full-graph fits within one SSD budget."""

import argparse
import csv
import io
import json
import os
import shutil
import subprocess
from pathlib import Path

from preflight_fullgraph import storage_plan


ROUTES = {"cpu": ("cpu", ""), "cuda": ("cuda", "0"),
          "cuda2": ("cuda", "0,1")}


def make_waves(rows, routes, available, rebuild, cpu_reserve=0,
               admission="worst_case"):
    if rows < 1_000 or rows > 1_000_000_000 or available <= 0:
        raise ValueError("Invalid rows or available SSD bytes")
    if cpu_reserve < 0:
        raise ValueError("CPU clustering reserve must be non-negative")
    if admission not in ("worst_case", "initial"):
        raise ValueError("Invalid graph-stage admission policy")
    if not routes or len(set(routes)) != len(routes) or any(
            route not in ROUTES for route in routes):
        raise ValueError("Choose distinct cpu, cuda, or cuda2 routes")
    capacity = available * 4 // 5
    waves = []
    current = []
    used = 0
    for route in routes:
        estimate = storage_plan(rows, "full", available,
                                rebuild_knn=rebuild)
        cost = estimate["worst_case_bytes" if
                        admission == "worst_case" else "required_bytes"]
        if route == "cpu":
            cost += cpu_reserve
        if cost > capacity:
            raise ValueError(f"{route} needs {cost} bytes; "
                             f"budget is {capacity} bytes")
        if current and (admission == "initial" or
                        used + cost > capacity):
            waves.append(current)
            current = []
            used = 0
        current.append({"route": route, "reserved_bytes": cost,
                        "later_graph_bound_bytes":
                            estimate["worst_case_bytes"]})
        used += cost
    waves.append(current)
    return waves


def submit_waves(waves, rows, available, rebuild, suite):
    active = subprocess.run(
        ["squeue", "-h", "-u", os.environ["USER"], "-o", "%j"],
        check=True, capture_output=True, text=True).stdout.splitlines()
    if any(name.startswith("feR_fg_") for name in active):
        raise RuntimeError("An earlier full-graph job is still active")
    prior = []
    submitted = []
    for number, wave in enumerate(waves, 1):
        current = []
        for item in wave:
            backend, devices = ROUTES[item["route"]]
            env = dict(os.environ, DEEP1B_FULLGRAPH_ROWS=str(rows),
                       DEEP1B_FIT_MODE="full",
                       DEEP1B_BACKEND_FILTER=backend,
                       DEEP1B_GPU_DEVICES=devices,
                       DEEP1B_QUOTA_FREE_BYTES=str(available),
                       DEEP1B_REBUILD_KNN_FOR_UMAP=str(int(rebuild)),
                       DEEP1B_AFTER_JOB=":".join(prior),
                       DEEP1B_DEPENDENCY_TYPE="afterok")
            result = subprocess.run(
                ["bash", str(suite / "submit_fullgraph5m.sh"), "deep"],
                env=env, check=True, capture_output=True, text=True)
            record = list(csv.DictReader(io.StringIO(result.stdout),
                                         delimiter="\t"))
            if len(record) != 1 or not record[0]["job"].isdigit():
                raise RuntimeError("Full-graph submission was blocked: "
                                   + result.stdout + result.stderr)
            job = record[0]["job"]
            current.append(job)
            submitted.append({"wave": number, "route": item["route"],
                              "job": job, "campaign": record[0]["campaign"]})
        prior = current
    return submitted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", type=int, default=1_000_000_000)
    parser.add_argument("--routes", default="cpu,cuda,cuda2")
    parser.add_argument("--quota-free-bytes", type=int, required=True)
    parser.add_argument("--physical-free-bytes", type=int)
    parser.add_argument("--cpu-clustering-reserve-bytes", type=int)
    parser.add_argument("--admission", choices=("worst_case", "initial"),
                        default="worst_case")
    parser.add_argument("--accept-late-space-failure", action="store_true")
    parser.add_argument("--retain-knn", action="store_true")
    parser.add_argument("--submit", action="store_true")
    args = parser.parse_args()
    if args.submit and args.physical_free_bytes is not None:
        parser.error("Physical free space must be measured when submitting")
    if args.submit and "cpu" in args.routes.split(",") and \
            (args.cpu_clustering_reserve_bytes is None or
             args.cpu_clustering_reserve_bytes <= 0):
        parser.error("CPU submission requires a positive clustering reserve")
    if args.submit and args.admission == "initial" and not \
            args.accept_late_space_failure:
        parser.error("Initial admission needs --accept-late-space-failure")
    suite = Path(__file__).resolve().parent
    base = Path(os.getenv("DEEP1B_BASE", "/scratch/firenze/NN"))
    physical = (args.physical_free_bytes if
                args.physical_free_bytes is not None else
                shutil.disk_usage(base).free)
    available = min(args.quota_free_bytes, physical)
    rebuild = not args.retain_knn and args.rows >= 100_000_000
    routes = args.routes.split(",")
    reserve = args.cpu_clustering_reserve_bytes or 0
    waves = make_waves(args.rows, routes, available, rebuild, reserve,
                       args.admission)
    plan = {"rows": args.rows, "available_bytes": available,
            "wave_budget_bytes": available * 4 // 5,
            "admission": args.admission,
            "later_space_failure_possible": args.admission == "initial",
            "cpu_clustering_reserve_bytes": reserve,
            "cpu_clustering_reserve_provided":
                args.cpu_clustering_reserve_bytes is not None,
            "excludes": ["input already on disk", "other jobs",
                         "unmeasured filesystem overhead"],
            "rebuild_knn": rebuild, "waves": waves,
            "simultaneous_reservation_bytes": max(
                sum(item["reserved_bytes"] for item in wave)
                for wave in waves),
            "unrestricted_reservation_bytes": sum(
                item["reserved_bytes"] for wave in waves
                for item in wave)}
    print(json.dumps(plan, indent=2))
    if args.submit:
        print(json.dumps(submit_waves(waves, args.rows, available,
                                      rebuild, suite), indent=2))


if __name__ == "__main__":
    main()
