#!/usr/bin/env python3
"""Prune audited binary outputs after their full-row figures are ready."""

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path

from audit_visuals import ROWS
from prune_comprehensive import active_jobs, job_ids


PAYLOADS = {
    "output.f32", "output.indices.u32", "output.distances.f32",
    "output.clusters.u32", "output.confidence.f32",
}


def complete_visual(record):
    if not record.get("visual_job"):
        return record["phase"] not in ROWS or record["repeat"] > 1
    campaign = Path(record["campaign"])
    output = Path(record["visual_output"]) / record["dataset"]
    manifest = output / "visual_manifest.csv"
    if not manifest.is_file():
        return False
    with manifest.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    expected = set()
    for case_file in campaign.glob("cases_*.tsv"):
        with case_file.open(newline="") as stream:
            for case in csv.DictReader(stream, delimiter="\t"):
                if case["mode"] not in ("pca", "umap", "tsne"):
                    continue
                views = ("xy", "xz", "yz") if case[
                    "components"] == "3" else ("xy",)
                expected.update((case["case"], view) for view in views)
    if (not rows or len(rows) != len(expected) or
            {(row["case"], row["view"]) for row in rows} != expected):
        return False
    count = ROWS[record["phase"]]
    for row in rows:
        if Path(row["image"]).name != row["image"]:
            return False
        image = output / row["image"]
        if (float(row["rows"]) != count or
                float(row["plotted_rows"]) != count or
                row["color_semantics"] != "none" or
                image.is_symlink() or not image.is_file() or
                image.stat().st_size == 0):
            return False
    return True


def completed_files(root, base, running):
    results = base / "fastEmbedR-results/massive-data"
    if (root.is_symlink() or root.resolve().parent !=
            (results / "comprehensive").resolve()):
        raise ValueError("Expected one comprehensive campaign directory")
    states = sorted(root.glob("*/*/state.json"))
    if not states:
        raise ValueError("Campaign has no lane state files")
    files = []
    skipped = []
    for state_file in states:
        state = json.loads(state_file.read_text())
        for record in state.get("records", []):
            campaign = Path(record["campaign"])
            dataset = "deep1b" if record["dataset"] == "deep" else "turing"
            expected = results / dataset
            if (campaign.is_symlink() or
                    campaign.resolve().parent != expected.resolve()):
                raise ValueError(f"Unexpected stage path: {campaign}")
            audit = campaign / "audit.json"
            if not audit.is_file() or json.loads(audit.read_text()).get(
                    "status") != "PASS":
                skipped.append((campaign, "stage audit not PASS"))
                continue
            jobs = job_ids(campaign / "jobs.tsv")
            jobs.update(str(record[key]) for key in
                        ("audit_job", "visual_job") if record.get(key))
            if jobs & running:
                skipped.append((campaign, "stage or plot job active"))
                continue
            if not complete_visual(record):
                skipped.append((campaign, "full-row figures incomplete"))
                continue
            for case in (campaign / "results").iterdir():
                if case.is_symlink() or not case.is_dir():
                    raise ValueError(f"Unexpected case directory: {case}")
                for name in sorted(PAYLOADS):
                    path = case / name
                    if path.is_symlink():
                        raise ValueError(f"Unexpected payload link: {path}")
                    if path.is_file():
                        files.append((path, path.stat().st_size))
    return files, skipped


def prune(root, base, running, apply=False):
    files, skipped = completed_files(root, base, running)
    total = sum(size for _, size in files)
    print(f"Eligible payloads: {len(files)}; bytes: {total}")
    for path, size in files:
        print(f"{size}\t{path}")
    for path, reason in skipped:
        print(f"SKIP\t{reason}\t{path}")
    if not apply:
        print("Dry run only. Add --apply after reviewing the paths.")
        return
    log = root / "pruned_payloads.tsv"
    first = not log.exists()
    with log.open("a", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        if first:
            writer.writerow(("timestamp_utc", "path", "bytes"))
        for path, size in files:
            path.unlink()
            writer.writerow((datetime.now(timezone.utc).isoformat(),
                             str(path), size))
            stream.flush()
    print("Removed only completed binary payloads; evidence remains.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("--base", type=Path,
                        default=Path("/scratch/firenze/NN"))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    prune(args.campaign, args.base.resolve(),
          active_jobs(), args.apply)


if __name__ == "__main__":
    main()
