#!/usr/bin/env python3
"""Cross-check the completed 11-dataset panel and Deep1B 100M run."""

import csv
import hashlib
import importlib.util
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


EXITS = (
    "results/m3-ultra-panel-v1-queue/panel_v6_20261102.launch.exit",
    "panel-v6/postprocess/supplement.exit",
    "panel-v6/postprocess/cpu_scaling.exit",
    "deep1b-100m-v3/queue100m/queue.exit",
    "deep1b-100m-v3/postprocess/postprocess.exit",
    "deep1b-100m-v3/report-controller/report.exit",
    "deep1b-100m-v3/layout-quality-controller/layout_quality.exit",
    "deep1b-100m-v3/installed-identity-controller/identity.exit",
)
MANIFESTS = (
    "panel-v6/postprocess/supplement.sha256",
    "panel-v6/postprocess/cpu_scaling.sha256",
    "deep1b-100m-v3/report-controller/report.sha256",
    "deep1b-100m-v3/layout-quality-controller/layout_quality.sha256",
    "deep1b-100m-v3/installed-identity-controller/identity.sha256",
)
EXPECTED = (
    ("panel-v6/postprocess/mac_panel_11datasets_v2.csv", 77),
    ("panel-v6/postprocess/mac_cpu_scaling_v1.csv", 462),
    ("panel-v6/postprocess/mac_cpu_scaling_v1_summary.csv", 42),
    ("deep1b-100m-v3/report/deep1b_100m_mac_stages.csv", 15),
    ("deep1b-100m-v3/layout-quality-v1/neighbor_vs_random.csv", 6),
)


def require(ok, message):
    if not ok:
        raise ValueError(message)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(8 * 1024 * 1024):
            result.update(block)
    return result.hexdigest()


def rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def inside(path, campaign):
    resolved = path.resolve()
    require(str(resolved).startswith(str(campaign) + "/"),
            f"Evidence path leaves campaign: {path}")
    return resolved


def verify_manifest(path, campaign):
    checked = []
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})\s+(.+)", line)
        require(match is not None, f"Malformed SHA-256 line: {path}")
        expected, name = match.groups()
        target = inside(Path(name), campaign)
        require(target.is_file() and digest(target) == expected,
                f"Report SHA-256 changed: {target}")
        checked.append(str(target))
    require(checked, f"Empty report SHA-256 manifest: {path}")
    return checked


def verify_sources(lock, current, base, campaign):
    require(lock.read_bytes() == current.read_bytes(),
            f"Source lock changed: {lock}")
    checked = 0
    for line in lock.read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})\s+(.+)", line)
        require(match is not None, f"Malformed source lock: {lock}")
        expected, name = match.groups()
        path = Path(name)
        if not path.is_absolute():
            path = base / path
        path = inside(path, campaign)
        require(path.is_file() and digest(path) == expected,
                f"Source changed after execution: {path}")
        checked += 1
    require(checked > 0, "Empty source lock")
    return checked


def panel_selector(campaign):
    source = (campaign / "panel-v6/benchmark/benchmarks/macos" /
              "derive_m3_ultra_selector_v2.py")
    spec = importlib.util.spec_from_file_location("panel_selector", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    queue = (campaign / "results/m3-ultra-panel-v1-queue" /
             "panel_v6_20261102")
    observations, hashes = module.observations(queue, campaign)
    require(len(observations) == 44 and len(hashes) == 11 * 8,
            "Panel selector did not verify every audited dataset")
    return queue, observations


def audit(campaign):
    campaign = campaign.resolve()
    require(str(campaign).startswith(
            "/Users/silvanopiazza/Documents/Stefano/"),
            "Final audit must run within Stefano")
    for name in EXITS:
        require((campaign / name).read_text().strip() == "0",
                f"Campaign stage did not complete: {name}")
    queue, observations = panel_selector(campaign)
    deep = campaign / "deep1b-100m-v3"
    panel_source_count = verify_sources(
        queue / "sources.lock", queue / "sources.current",
        campaign, campaign)
    deep_source_count = verify_sources(
        deep / "queue100m/sources.lock",
        deep / "queue100m/sources.current", deep, campaign)
    files = []
    for name in MANIFESTS:
        files.extend(verify_manifest(campaign / name, campaign))
    counts = {}
    for name, expected in EXPECTED:
        observed = len(rows(campaign / name))
        require(observed == expected, f"Report row count changed: {name}")
        counts[name] = observed
    structural = json.loads(
        (deep / "postprocess-audit-v1/audit.json").read_text())
    require(structural.get("status") == "passed" and
            structural.get("rows") == 100_000_000 and
            structural.get("neighbors") == 30 and
            structural.get("stage_count") == 15,
            "Deep1B structural audit summary changed")
    graph = rows(deep / "postprocess-audit-v1/graph_audit.csv")
    require(len(graph) == 1 and int(graph[0]["rows"]) == 100_000_000
            and int(graph[0]["neighbors"]) == 30 and
            int(graph[0]["recall_sample_size"]) == 32,
            "Deep1B graph audit summary changed")
    identity = json.loads(
        (deep / "installed-identity-audit-v1/identity.json").read_text())
    require(identity.get("status") == "passed",
            "Installed package identity audit changed")
    out = campaign / "final-campaign-audit-v1"
    out.mkdir(exist_ok=False)
    record = {
        "status": "benchmark_evidence_verified",
        "panel_datasets": 11, "panel_selector_observations":
            len(observations),
        "deep1b_rows": 100_000_000, "deep1b_neighbors": 30,
        "deep1b_sample_recall_gate_pass":
            graph[0]["recall_gate_pass"],
        "panel_locked_sources": panel_source_count,
        "deep1b_locked_sources": deep_source_count,
        "report_hashes_verified": len(files),
        "report_rows": counts,
        "completed_utc": datetime.now(timezone.utc).isoformat(),
        "manuscript_integration": "pending_local_copy_and_review",
    }
    (out / "audit.json").write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n")
    print("Verified complete Mac benchmark evidence; manuscript pending")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: script.py CAMPAIGN_ROOT")
    audit(Path(sys.argv[1]))
