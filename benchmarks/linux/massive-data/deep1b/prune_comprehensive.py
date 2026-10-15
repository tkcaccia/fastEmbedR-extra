#!/usr/bin/env python3
"""Remove one inactive comprehensive campaign and its generated outputs."""

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


def job_ids(ledger):
    if not ledger.is_file():
        raise ValueError(f"Missing job ledger: {ledger}")
    with ledger.open(newline="") as stream:
        rows = csv.DictReader(stream, delimiter="\t")
        return {match.group() for row in rows
                for value in (row.get("controller"), row.get("job_id"))
                if value and (match := re.fullmatch(r"\d+", value))}


def campaign_paths(root, results):
    root = root.resolve()
    results = results.resolve()
    if root.parent != results / "comprehensive" or not root.is_dir():
        raise ValueError("Expected one comprehensive campaign directory")
    states = sorted(root.glob("*/*/state.json"))
    if not states:
        raise ValueError("Campaign has no lane state files")
    paths = {root}
    jobs = job_ids(root / "jobs.tsv")
    allowed = {results / name for name in
               ("deep1b", "turing", "full_layouts")}
    for state_file in states:
        state = json.loads(state_file.read_text())
        for key in ("pilot_controller", "final_controller"):
            if state.get(key):
                jobs.add(str(state[key]))
        for record in state.get("records", []):
            for key in ("campaign", "visual_output"):
                value = record.get(key)
                if not value:
                    continue
                source = Path(value)
                if source.is_symlink():
                    raise ValueError(f"Unexpected output path: {source}")
                path = source.resolve()
                if path.parent not in allowed:
                    raise ValueError(f"Unexpected output path: {path}")
                paths.add(path)
            for key in ("audit_job", "visual_job"):
                if record.get(key):
                    jobs.add(str(record[key]))
            stage = Path(record["campaign"]) / "jobs.tsv"
            if stage.parent.is_dir():
                jobs.update(job_ids(stage))
    return paths, jobs


def active_jobs():
    user = os.environ.get("USER")
    if not user:
        raise ValueError("USER is required for Slurm safety check")
    output = subprocess.check_output(
        ["squeue", "-h", "-u", user, "-o", "%A"], text=True)
    return set(output.split())


def require_inactive(jobs, running):
    active = jobs & running
    if active:
        raise ValueError("Refusing to remove active jobs: " +
                         ", ".join(sorted(active)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("--base", type=Path,
                        default=Path("/scratch/firenze/NN"))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    results = (args.base.resolve() / "fastEmbedR-results" /
               "massive-data")
    paths, jobs = campaign_paths(args.campaign.resolve(), results)
    require_inactive(jobs, active_jobs())
    present = sorted((path for path in paths if path.is_dir()),
                     key=lambda path: len(path.parts), reverse=True)
    print(f"Inactive campaign; generated directories: {len(present)}")
    for path in present:
        print(path)
    if not args.apply:
        print("Dry run only. Add --apply to remove these directories.")
        return
    for path in present:
        shutil.rmtree(path)
    print("Removed campaign outputs; BigANN source data was untouched.")


if __name__ == "__main__":
    main()
