#!/usr/bin/env python3
"""Submit independent CPU/GPU scaling lanes after HNSW calibration."""

import csv
import json
import os
import subprocess
import sys
from pathlib import Path

from full_graph_gate import plan as full_graph_plan


PLOT_ROWS = {"scale": 1_000_000, "fresh5m": 5_000_000,
             "fresh5m_3d": 5_000_000, "scale10m": 10_000_000,
             "boundary": 100_000_000, "billion": 1_000_000_000}


def save_ledger(path, rows):
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle,
            ("dataset", "lane", "phase", "campaign",
             "visual_job", "visual_output"), delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def queue_plot(base, campaign, dataset, lane, phase):
    suite = base / "benchmark_scripts/massive-data/visualization"
    scripts = [suite / "render_full_layouts.R",
               suite / "slurm_full_layouts.sh"]
    if any(not path.is_file() for path in scripts):
        raise RuntimeError("Full-row visualization scripts are missing")
    with (campaign / "jobs.tsv").open(newline="") as handle:
        audits = [row["job_id"] for row in
            csv.DictReader(handle, delimiter="\t")
            if row["kind"] == "audit"]
    if len(audits) != 1:
        raise RuntimeError("Campaign has no unique audit job")
    out = campaign / "full_row_plots"
    out.mkdir(exist_ok=True)
    digest = subprocess.check_output(["sha256sum", str(base /
        "singularity/fastembedr_cuda.sif"), *(str(p) for p in scripts)],
        text=True)
    expected_image = (campaign / "image.sha256").read_text().split()[0]
    if digest.split()[0] != expected_image:
        raise RuntimeError("Plot image differs from the fitted campaign")
    (out / "source.sha256").write_text(digest)
    index = "0" if dataset == "deep" else "1"
    exported = (f"ALL,VIS_BASE={base},VIS_SUITE={suite},VIS_OUT={out},"
                f"VIS_ROWS={PLOT_ROWS[phase]},VIS_CAMPAIGN={campaign}")
    command = ["sbatch", "--parsable", "--account=" +
        os.environ.get("DEEP1B_CPU_ACCOUNT", "immunology"),
        "--partition=" + os.environ.get("DEEP1B_CPU_PARTITION", "ada"),
        "--chdir=" + str(base), "--array=" + index,
        "--dependency=afterany:" + audits[0],
        "--output=" + str(base / "benchmark_logs/feR_plot_%A_%a.out"),
        "--error=" + str(base / "benchmark_logs/feR_plot_%A_%a.err"),
        "--export=" + exported, str(scripts[1])]
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError("Plot submission: " + result.stderr)
    return result.stdout.strip(), str(out)


def submit(root):
    audit = json.loads((root / "audit_representative.json").read_text())
    if not audit.get("complete"):
        raise RuntimeError("Representative HNSW audit failed")
    image_hash = (root / "source.sha256").read_text().split()[0]
    base = Path(os.environ.get("DEEP1B_BASE", "/scratch/firenze/NN"))
    suite = base / "benchmark_scripts/massive-data/deep1b"
    runner = base / "benchmark_scripts/massive-data/run_scaling.R"
    image = base / "singularity/fastembedr_cuda.sif"
    actual = subprocess.check_output(["sha256sum", str(image)],
                                     text=True).split()[0]
    if actual != image_hash:
        raise RuntimeError("SIF changed after representative pilot")
    with (root / "selected.csv").open(newline="") as handle:
        selected = {row["dataset"]: row for row in csv.DictReader(handle)
                    if row["shard_rows"] == "50000"}
    for dataset in ("deep", "turing"):
        if dataset in selected and selected[dataset]["image_sha256"] != actual:
            raise RuntimeError("Selected controls use a different image")
    full_graph_plan(root)
    launches = []
    ledger = root / "followup_submissions.tsv"
    if ledger.is_file():
        with ledger.open(newline="") as handle:
            launches = list(csv.DictReader(handle, delimiter="\t"))
    if selected_250k(root):
        if not (root / "large_probe_campaign.txt").exists():
            command = ["bash", str(base /
                "benchmark_scripts/massive-data/hnsw-autotune/"
                "submit_large_probe.sh"), str(root)]
            result = subprocess.run(command, cwd=base, text=True,
                                    capture_output=True)
            if result.returncode:
                raise RuntimeError("Large recall probe: " + result.stderr)
            campaign = next((line.removeprefix("Campaign: ")
                for line in result.stdout.splitlines()
                if line.startswith("Campaign: ")), "")
            if not campaign:
                raise RuntimeError("Large recall probe has no campaign path")
            (root / "large_probe_campaign.txt").write_text(campaign + "\n")
            print("large recall probe", campaign, flush=True)
    for dataset in ("deep", "turing"):
        for lane in ("cpu", "cuda"):
            phases = ["scale", "fresh5m", "fresh5m_3d", "scale10m",
                      "boundary", "billion"]
            if lane == "cpu":
                phases.append("threads1m")
            if lane == "cuda" or dataset in selected:
                phases.append("graph10m")
            for phase in phases:
                prior = next((row for row in launches
                    if row["dataset"] == dataset and row["lane"] == lane
                    and row["phase"] == phase), None)
                if prior is not None:
                    if phase in PLOT_ROWS and not prior.get("visual_job"):
                        prior["visual_job"], prior["visual_output"] = \
                            queue_plot(base, Path(prior["campaign"]),
                                       dataset, lane, phase)
                        save_ledger(ledger, launches)
                    continue
                env = os.environ.copy()
                env.update(DEEP1B_BASE=str(base), DEEP1B_SUITE=str(suite),
                           DEEP1B_RUNNER=str(runner),
                           DEEP1B_ONLY_BACKEND=lane,
                           DEEP1B_SERIALIZE="0" if lane == "cpu" else "1",
                           DEEP1B_ALLOW_BILLION="1",
                           FASTEMBEDR_IMAGE_SHA256=actual)
                if phase == "graph10m" and lane == "cpu":
                    controls = selected[dataset]
                    env.update(DEEP1B_HNSW_M=controls["m"],
                               DEEP1B_HNSW_EFC=controls["ef_construction"],
                               DEEP1B_HNSW_EFS=controls["ef_search"])
                result = subprocess.run(["bash", str(suite / "submit.sh"),
                                         phase, dataset], cwd=base, env=env,
                                        text=True, capture_output=True)
                if result.returncode:
                    raise RuntimeError(f"{dataset}/{lane}/{phase}: " +
                                       result.stderr)
                campaign = next((line.removeprefix("Campaign: ")
                    for line in result.stdout.splitlines()
                    if line.startswith("Campaign: ")), "")
                if not campaign:
                    raise RuntimeError("Submission omitted campaign path")
                launches.append(dict(dataset=dataset, lane=lane,
                                     phase=phase, campaign=campaign))
                save_ledger(ledger, launches)
                if phase in PLOT_ROWS:
                    launches[-1]["visual_job"], \
                        launches[-1]["visual_output"] = queue_plot(
                            base, Path(campaign), dataset, lane, phase)
                    save_ledger(ledger, launches)
                print(dataset, lane, phase, campaign, flush=True)
    return launches


def selected_250k(root):
    with (root / "selected.csv").open(newline="") as handle:
        return any(row["shard_rows"] == "250000"
                   for row in csv.DictReader(handle))


if __name__ == "__main__":
    submit(Path(sys.argv[1]))
