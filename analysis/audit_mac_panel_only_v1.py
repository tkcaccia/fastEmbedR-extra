#!/usr/bin/env python3
"""Independently close the Mac panel after Deep1B was postponed."""

import csv
import importlib.util
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path


EXITS = (
    "results/m3-ultra-panel-v1-queue/panel_v6_20261102.launch.exit",
    "panel-v6/postprocess/supplement.exit",
    "panel-v6/postprocess/cpu_scaling.exit",
)
MANIFESTS = (
    "panel-v6/postprocess/supplement.sha256",
    "panel-v6/postprocess/cpu_scaling.sha256",
)
COUNTS = (
    ("panel-v6/postprocess/mac_panel_11datasets_v2.csv", 77),
    ("panel-v6/postprocess/mac_cpu_scaling_v1.csv", 462),
    ("panel-v6/postprocess/mac_cpu_scaling_v1_summary.csv", 42),
)


def load_helpers(campaign):
    path = (campaign / "final-audit-controller" /
            "audit_mac_campaign_complete_v1.py")
    spec = importlib.util.spec_from_file_location("mac_audit_helpers", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def verify_metal(campaign, queue, helpers):
    status = run_rows(queue / "status.csv")
    result = {}
    for row in status:
        dataset = row["dataset"]
        if dataset == "queue":
            continue
        run = campaign / "results/m3-ultra-panel-v1" / row["run_id"]
        panel = json.loads((run / "panel_audit.json").read_text())
        helpers.require(panel.get("execution_status") == "passed" and
                        panel.get("issues") == [],
                        f"Execution issues remain: {dataset}")
        arms = run_rows(run / "benchmark_runs.csv")
        metal = [arm for arm in arms if "_metal" in arm["method"]]
        helpers.require(len(arms) == 147 and len(metal) == 21,
                        f"Incomplete Metal arm set: {dataset}")
        for arm in metal:
            observed = float(arm["metal_allocated_bytes_observed"])
            helpers.require(arm["actual_backend"] == "metal" and
                            math.isfinite(observed) and observed > 0,
                            f"Metal execution unverified: {dataset}")
        result[dataset] = len(metal)
    helpers.require(len(result) == 11, "Panel dataset count changed")
    return result


def audit(campaign):
    campaign = campaign.resolve()
    if not str(campaign).startswith(
            "/Users/silvanopiazza/Documents/Stefano/"):
        raise ValueError("Panel audit must run within Stefano")
    helpers = load_helpers(campaign)
    for name in EXITS:
        helpers.require((campaign / name).read_text().strip() == "0",
                        f"Panel stage did not pass: {name}")
    deep = campaign / "deep1b-100m-v3"
    postponement = (deep / "postponement_20261102.txt").read_text()
    helpers.require("stage_count_started=0" in postponement and
                    (deep / "queue100m/queue.exit").read_text().strip()
                    != "0" and
                    (deep / "queue100m/status.csv").read_text().strip()
                    == "stage,status,seconds",
                    "The postponed Deep1B queue has unexpected work")
    queue, observations = helpers.panel_selector(campaign)
    locked = helpers.verify_sources(
        queue / "sources.lock", queue / "sources.current",
        campaign, campaign)
    verified = []
    for name in MANIFESTS:
        verified.extend(helpers.verify_manifest(
            campaign / name, campaign))
    counts = {}
    for name, expected in COUNTS:
        observed = len(run_rows(campaign / name))
        helpers.require(observed == expected,
                        f"Panel report row count changed: {name}")
        counts[name] = observed
    metal = verify_metal(campaign, queue, helpers)
    out = campaign / "panel-only-audit-v1"
    out.mkdir(exist_ok=False)
    record = {
        "status": "panel_evidence_verified",
        "datasets": 11,
        "selector_observations": len(observations),
        "metal_arms_verified": metal,
        "locked_sources": locked,
        "report_hashes_verified": len(verified),
        "report_rows": counts,
        "deep1b_100m": "postponed_before_first_stage",
        "completed_utc": datetime.now(timezone.utc).isoformat(),
    }
    (out / "audit.json").write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n")
    print("Verified the 11-dataset Mac panel independently of Deep1B")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: script.py CAMPAIGN_ROOT")
    audit(Path(sys.argv[1]))
