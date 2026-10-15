#!/usr/bin/env python3
"""Advance one source-locked massive-data stage per Slurm controller job."""

import csv
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import audit_visuals


def save(root, state):
    temporary = root / "state.json.tmp"
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(root / "state.json")


def load(root):
    return json.loads((root / "state.json").read_text())


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def selected_controls(rows, dataset):
    candidates = [row for row in rows
                  if row["dataset"] == dataset and
                  row["split"] == "tune" and
                  row["recall_gate"] == "True" and
                  row["consistency_gate"] == "True"]
    if not candidates:
        return None
    best = min(candidates, key=lambda row:
               float(row["build_seconds"]) +
               float(row["query_seconds"]))
    return {key: int(best[key]) for key in
            ("m", "ef_construction", "ef_search")}


def make_plan(repeats, candidates):
    plan = []
    for repeat in range(1, repeats + 1):
        for phase, dataset, lane in (
            ("threads1m", "deep", "cpu"),
            ("threads1m", "turing", "cpu"),
            ("fresh5m", "deep", "cpu"),
            ("fresh5m", "turing", "cpu"),
        ):
            plan.append(dict(phase=phase, dataset=dataset, lane=lane,
                             repeat=repeat))
    plan.append(dict(phase="screen", dataset="both", lane="cpu",
                     repeat=1))
    for dataset in ("deep", "turing"):
        plan.append(dict(phase="fresh5m_graph", dataset=dataset,
                         lane="cpu", repeat=1, policy="shape"))
        if candidates[dataset]:
            plan.append(dict(phase="fresh5m_graph", dataset=dataset,
                             lane="cpu", repeat=1, policy="selected",
                             controls=candidates[dataset]))
    for repeat in range(1, repeats + 1):
        for dataset in ("deep", "turing"):
            plan.append(dict(phase="fresh5m", dataset=dataset,
                             lane="cuda", repeat=repeat))
    for dataset in ("deep", "turing"):
        plan.append(dict(phase="fresh5m_graph", dataset=dataset,
                         lane="cuda", repeat=1, policy="shape"))
    return plan


def make_extended_plan(lane):
    if lane not in ("cpu", "cuda"):
        raise ValueError("Extended lane must be cpu or cuda")
    return [dict(phase=phase, dataset=dataset, lane=lane, repeat=1)
            for phase in ("cluster_pilot", "cluster_scale", "fresh5m_3d",
                          "boundary", "billion")
            for dataset in ("deep", "turing")]


def make_comprehensive_plan(lane, repeats, dataset=None):
    if lane not in ("cpu", "cuda") or repeats < 1:
        raise ValueError("Expected cpu/cuda and at least one repeat")
    if dataset not in (None, "deep", "turing"):
        raise ValueError("Expected deep or turing")
    datasets = ("deep", "turing") if dataset is None else (dataset,)
    plan = []
    for phase, count in (("pilot", 1), ("scale", repeats),
                         ("threads1m", 1 if lane == "cpu" else 0),
                         ("fresh5m", repeats),
                         ("fresh5m_3d", 1),
                         ("scale10m", repeats),
                         ("boundary", 1), ("billion", 1),
                         ("graph10m", 1)):
        for repeat in range(1, count + 1):
            for name in datasets:
                plan.append(dict(phase=phase, dataset=name,
                                 lane=lane, repeat=repeat))
    return plan


def initialize_comprehensive(root, lane, repeats, base, dataset):
    digest = os.environ.get("FASTEMBEDR_IMAGE_SHA256", "")
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Missing source-locked image SHA-256")
    state = dict(status="RUNNING", created=timestamp(), base=str(base),
                 lane=lane, dataset=dataset, strict_audit=False,
                 comprehensive=True,
                 refinement_image=digest,
                 plan=make_comprehensive_plan(lane, repeats, dataset),
                 records=[], quality_gaps=[])
    save(root, state)
    return state


def initialize_extended(root, previous, lane, base):
    old = json.loads((previous / "state.json").read_text())
    if old["status"] not in ("PASS", "QUALITY_GAPS") or any(
        not record.get("audited") for record in old["records"]
    ) or len(old["records"]) != len(old["plan"]):
        raise ValueError("The 5M campaign has not finished its audits")
    state = dict(status="RUNNING", created=timestamp(), base=str(base),
                 previous=str(previous), lane=lane, strict_audit=True,
                 refinement_image=old["refinement_image"],
                 plan=make_extended_plan(lane), records=[],
                 quality_gaps=list(old.get("quality_gaps", [])))
    save(root, state)
    return state


def initialize(root, refinement, repeats, base):
    audit = json.loads((refinement / "audit_refine.json").read_text())
    if not audit.get("complete"):
        raise ValueError("HNSW refinement is incomplete; inspect its audit")
    with (refinement / "refine_5m.csv").open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 36:
        raise ValueError("HNSW refinement has an incomplete effort grid")
    candidates = {name: selected_controls(rows, name)
                  for name in ("deep", "turing")}
    gaps = []
    for name in ("deep", "turing"):
        if not candidates[name]:
            gaps.append(f"{name}: no tuning-half HNSW candidate passed")
    if audit.get("gated_holdout", 0) < 3:
        gaps.append("HNSW refinement holdout missed a recall gate")
    state = dict(status="RUNNING", created=timestamp(),
                 refinement=str(refinement), base=str(base),
                 refinement_image=(refinement / "source.sha256")
                 .read_text().split()[0],
                 candidates=candidates,
                 plan=make_plan(repeats, candidates),
                 records=[], quality_gaps=gaps)
    save(root, state)
    return state


def audit_previous(state, record):
    campaign = Path(record["campaign"])
    if record["phase"] == "screen":
        report = json.loads((campaign / "audit_5m.json").read_text())
        if not report.get("complete"):
            raise ValueError("exact-reference screen is incomplete")
        if report.get("recall_passes", 0) < 3:
            state["quality_gaps"].append(
                "exact-reference screen missed a recall gate")
        state["truth_campaign"] = str(campaign)
    else:
        report = json.loads((campaign / "audit.json").read_text())
        failures = report.get("failures", [])
        if state.get("strict_audit") and failures:
            raise ValueError("benchmark stage failed: " + "; ".join(failures))
        hard = [item for item in failures if
                "sampled KNN recall" not in item and
                "exact KNN quality" not in item]
        if hard:
            raise ValueError("benchmark stage failed: " + "; ".join(hard))
        state["quality_gaps"].extend(failures)
        if report.get("case_count", 0) < 1:
            raise ValueError("benchmark stage has no audited cases")
    record["audited"] = timestamp()


def parse_submission(output, is_screen):
    campaign = re.search(r"^Campaign: (/.+)$", output, re.M)
    if not campaign:
        raise ValueError("submission did not print a campaign path")
    path = Path(campaign.group(1))
    if is_screen:
        job = re.search(r"^Audit job: (\d+)$", output, re.M)
        if not job:
            raise ValueError("screen did not print an audit job")
        return path, job.group(1)
    with (path / "jobs.tsv").open(newline="") as handle:
        audit = [row for row in csv.DictReader(handle, delimiter="\t")
                 if row["kind"] == "audit"]
    if len(audit) != 1 or not audit[0]["job_id"].isdigit():
        raise ValueError("submission ledger has no unique audit job")
    return path, audit[0]["job_id"]


def submit_stage(state, stage):
    base = Path(state["base"])
    suite = base / "benchmark_scripts/massive-data"
    case_suite = Path(os.environ.get("DEEP1B_SUITE",
        suite / "deep1b"))
    env = os.environ.copy()
    if stage["phase"] == "screen":
        command = ["bash", str(suite / "hnsw-autotune/submit_5m.sh"),
                   "screen"]
    else:
        command = ["bash", str(case_suite / "submit.sh"),
                   stage["phase"], stage["dataset"]]
        env["DEEP1B_ONLY_BACKEND"] = stage["lane"]
        env["DEEP1B_SERIALIZE"] = (
            "0" if state.get("comprehensive") else "1")
        if stage["phase"] == "billion":
            env["DEEP1B_ALLOW_BILLION"] = "1"
        if stage["phase"] == "fresh5m_graph":
            env["DEEP1B_TRUTH_CAMPAIGN"] = state["truth_campaign"]
        if stage.get("policy") == "selected":
            controls = stage["controls"]
            env["DEEP1B_HNSW_M"] = str(controls["m"])
            env["DEEP1B_HNSW_EFC"] = str(
                controls["ef_construction"])
            env["DEEP1B_HNSW_EFS"] = str(controls["ef_search"])
    result = subprocess.run(command, cwd=base, env=env, text=True,
                            capture_output=True)
    print(result.stdout, end="", flush=True)
    print(result.stderr, end="", file=sys.stderr, flush=True)
    if result.returncode:
        raise RuntimeError(f"stage submission exited {result.returncode}")
    return parse_submission(result.stdout, stage["phase"] == "screen")


def queue_visual(state, record):
    if "VIS_SUITE" not in os.environ:
        return
    row_counts = {"pilot": 20_000, "scale": 1_000_000,
                  "fresh5m": 5_000_000,
                  "fresh5m_3d": 5_000_000,
                  "scale10m": 10_000_000,
                  "boundary": 100_000_000, "billion": 1_000_000_000}
    phase = record["phase"]
    if phase not in row_counts:
        return
    repeats = [item["repeat"] for item in state["plan"]
               if item["phase"] == phase and
               item["dataset"] == record["dataset"]]
    if record["repeat"] != min(repeats):
        return
    base = Path(state["base"])
    suite = Path(os.environ["VIS_SUITE"])
    rows = row_counts[phase]
    parent = base / "fastEmbedR-results/massive-data/full_layouts"
    image = Path(record["campaign"]) / "image.sif"
    pinned = (Path(record["campaign"]) / "image.sha256").read_text()
    if pinned.split() != [state["refinement_image"], str(image)]:
        raise RuntimeError("Plot image differs from campaign image")
    digest = pinned + subprocess.check_output(["sha256sum",
        str(suite / "render_full_layouts.R"),
        str(suite / "slurm_full_layouts.sh")], text=True)
    parent.mkdir(parents=True, exist_ok=True)
    prefix = (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") +
              f"_{state['lane']}_{record['dataset']}_{phase}_{rows}_")
    out = Path(tempfile.mkdtemp(prefix=prefix, dir=parent))
    (out / "source.sha256").write_text(digest)
    array = "0" if record["dataset"] == "deep" else "1"
    export = (f"ALL,VIS_BASE={base},VIS_SUITE={suite},"
              f"VIS_OUT={out},VIS_ROWS={rows},"
              f"VIS_CAMPAIGN={record['campaign']},VIS_IMAGE={image}")
    result = subprocess.run(["sbatch", "--parsable",
        "--account=" + os.environ.get("DEEP1B_CPU_ACCOUNT", "immunology"),
        "--partition=" + os.environ.get("DEEP1B_CPU_PARTITION", "ada"),
        "--chdir=" + str(base), "--array=" + array,
        "--output=" + str(base / "benchmark_logs/feR_fullplot_%A_%a.out"),
        "--error=" + str(base / "benchmark_logs/feR_fullplot_%A_%a.err"),
        *(["--dependency=afterany:" + record["audit_job"]]
          if record.get("audit_job") else []),
        "--export=" + export, str(suite / "slurm_full_layouts.sh")],
        capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("plot submission failed: " + result.stderr)
    record["visual_job"] = result.stdout.strip()
    record["visual_output"] = str(out)


def queue_controller(root, index, dependencies, state):
    base = Path(state["base"])
    suite = Path(os.environ.get("DEEP1B_SUITE",
        base / "benchmark_scripts/massive-data/deep1b"))
    name = "feR_auto"
    if state.get("comprehensive"):
        step = "fanout" if index == 1 else "final"
        name = f"feR_{state['lane']}_{state['dataset']}_{step}"
    command = ["sbatch", "--parsable",
        "--account=" + os.environ.get("DEEP1B_CPU_ACCOUNT", "immunology"),
        "--partition=" + os.environ.get("DEEP1B_CPU_PARTITION", "ada"),
        "--chdir=" + str(base), "--job-name=" + name,
        "--cpus-per-task=1", "--mem=2G", "--time=00:20:00",
        "--dependency=afterany:" + ":".join(dict.fromkeys(dependencies)),
        "--output=" + str(base / "benchmark_logs/feR_auto_%j.out"),
        "--error=" + str(base / "benchmark_logs/feR_auto_%j.err"),
        "--export=ALL,DEEP1B_PIPELINE=" + str(root) +
            ",DEEP1B_STAGE=" + str(index),
        str(suite / "controller.sbatch")]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("controller not queued: " + result.stderr)
    return result.stdout.strip()


def advance_comprehensive(root, index):
    state = load(root)
    plan = state["plan"]
    if index == 0:
        if state["records"] or state["status"] != "RUNNING":
            raise ValueError("comprehensive pilot already submitted")
        base = Path(state["base"])
        image = Path(os.environ.get("DEEP1B_IMAGE",
                     base / "singularity/fastembedr_cuda.sif"))
        digest = subprocess.check_output(["sha256sum", str(image)],
                                         text=True).split()[0]
        if digest != state["refinement_image"]:
            raise ValueError("image differs from campaign identity")
        if plan[0]["phase"] != "pilot":
            raise ValueError("comprehensive plan needs a pilot first")
        campaign, audit_job = submit_stage(state, plan[0])
        state["records"].append(dict(index=0, **plan[0],
                                     campaign=str(campaign),
                                     audit_job=audit_job,
                                     submitted=timestamp()))
        save(root, state)
        state["pilot_controller"] = queue_controller(
            root, 1, [audit_job], state)
        save(root, state)
        return
    if index == 1:
        if state["status"] != "RUNNING" or not state["records"]:
            raise ValueError("comprehensive pilot is missing")
        pilot = state["records"][0]
        if not pilot.get("audited"):
            audit_previous(state, pilot)
        if not pilot.get("visual_job"):
            queue_visual(state, pilot)
        save(root, state)
        for position in range(len(state["records"]), len(plan)):
            stage = plan[position]
            campaign, audit_job = submit_stage(state, stage)
            record = dict(index=position, **stage,
                          campaign=str(campaign), audit_job=audit_job,
                          submitted=timestamp())
            state["records"].append(record)
            save(root, state)
            queue_visual(state, record)
            save(root, state)
        dependencies = [item["audit_job"] for item in state["records"]]
        dependencies += [item["visual_job"] for item in state["records"]
                         if item.get("visual_job")]
        state["status"] = "WAITING"
        state["final_controller"] = queue_controller(
            root, len(plan), dependencies, state)
        save(root, state)
        return
    if index != len(plan) or state["status"] != "WAITING":
        raise ValueError("invalid comprehensive finalization")
    failures = []
    for record in state["records"]:
        if record.get("audited"):
            continue
        try:
            audit_previous(state, record)
        except Exception as error:
            failures.append(f"{record['phase']} repeat "
                            f"{record['repeat']}: {error}")
    save(root, state)
    visual = audit_visuals.audit(root)
    state = load(root)
    if failures:
        state["status"] = "STOPPED"
        state["failure"] = "; ".join(failures)
        save(root, state)
    print("Comprehensive audit:", state["status"],
          "visual images:", visual["images_checked"])
    if failures or visual["status"] != "PASS":
        raise RuntimeError(state.get("failure", "visual audit failed"))


def advance(root, index):
    state = load(root)
    base = Path(state["base"])
    subprocess.run(["sha256sum", "-c", str(root / "code.sha256")],
                   check=True, stdout=subprocess.DEVNULL)
    if state.get("comprehensive"):
        advance_comprehensive(root, index)
        return
    if state["status"] != "RUNNING" or len(state["records"]) != index:
        raise ValueError("controller index or pipeline state mismatch")
    if index == 0:
        image = Path(os.environ.get("DEEP1B_IMAGE",
                    base / "singularity/fastembedr_cuda.sif"))
        digest = subprocess.check_output(["sha256sum", str(image)],
                                         text=True).split()[0]
        if digest != state["refinement_image"]:
            raise ValueError("image differs from the HNSW refinement")
    else:
        audit_previous(state, state["records"][-1])
        queue_visual(state, state["records"][-1])
    if index == len(state["plan"]):
        state["status"] = ("QUALITY_GAPS" if state["quality_gaps"]
                           else "PASS")
        state["finished"] = timestamp()
        save(root, state)
        print("Pipeline finished:", state["status"])
        return
    stage = state["plan"][index]
    campaign, audit_job = submit_stage(state, stage)
    state["records"].append(dict(index=index, **stage,
                                 campaign=str(campaign),
                                 audit_job=audit_job,
                                 submitted=timestamp()))
    save(root, state)
    job = queue_controller(root, index + 1, [audit_job], state)
    print("Next controller:", job)


def main():
    command = sys.argv[1]
    root = Path(sys.argv[2]).resolve()
    if command == "init":
        initialize(root, Path(sys.argv[3]).resolve(), int(sys.argv[4]),
                   Path(sys.argv[5]).resolve())
    elif command == "init_extended":
        initialize_extended(root, Path(sys.argv[3]).resolve(),
                            sys.argv[4], Path(sys.argv[5]).resolve())
    elif command == "init_comprehensive":
        initialize_comprehensive(root, sys.argv[3],
                                 int(sys.argv[4]),
                                 Path(sys.argv[5]).resolve(),
                                 sys.argv[6])
    elif command == "advance":
        try:
            advance(root, int(sys.argv[3]))
        except Exception as error:
            state = load(root)
            state["status"] = "STOPPED"
            state["failure"] = str(error)
            save(root, state)
            raise
    else:
        raise ValueError("Expected init or advance")


if __name__ == "__main__":
    main()
