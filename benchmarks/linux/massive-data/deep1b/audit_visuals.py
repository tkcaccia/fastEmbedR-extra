#!/usr/bin/env python3
"""Verify that every scheduled all-point layout image was produced."""

import csv
import json
import sys
from pathlib import Path


ROWS = {"pilot": 20_000, "scale": 1_000_000,
        "fresh5m": 5_000_000,
        "fresh5m_3d": 5_000_000,
        "scale10m": 10_000_000, "boundary": 100_000_000,
        "billion": 1_000_000_000}


def figure_failures(campaign, output, expected, count):
    audit_file = campaign / "audit.json"
    if not audit_file.is_file() or json.loads(
            audit_file.read_text()).get("status") != "PASS":
        return []
    cases = {case for case, view in expected if view == "xy"}
    backends = {case.split("_")[0] for case in cases}
    required = {}
    for backend in backends:
        methods = {mode: [case for case in cases
                          if case.startswith(f"{backend}_{mode}_")]
                   for mode in ("pca", "tsne", "umap")}
        if all(len(items) == 1 for items in methods.values()):
            required[backend] = {key: value[0] for key, value
                                 in methods.items()}
    if not required:
        return []
    manifest = output / "figure_manifest.csv"
    if not manifest.is_file():
        return [f"missing manuscript figure manifest: {manifest}"]
    with manifest.open(newline="") as stream:
        figures = list(csv.DictReader(stream))
    failures = []
    for backend, methods in required.items():
        matches = [row for row in figures
                   if row.get("backend") == backend]
        if len(matches) != 1:
            failures.append(f"missing or duplicate {backend} figure")
            continue
        try:
            row = matches[0]
            image = output / row["image"]
            valid = (all(row[mode] == case for mode, case in
                         methods.items()) and
                     float(row["rows"]) == count and
                     row["color_semantics"] == "none" and
                     Path(row["image"]).name == row["image"] and
                     not image.is_symlink() and image.is_file() and
                     image.stat().st_size > 0)
        except (KeyError, ValueError, OSError):
            valid = False
        if not valid:
            failures.append(f"incomplete {backend} manuscript figure")
    return failures


def audit(root):
    state = json.loads((root / "state.json").read_text())
    failures = []
    checked = 0
    required = {(row["phase"], row["dataset"])
                for row in state["plan"] if row["phase"] in ROWS}
    scheduled = {(row["phase"], row["dataset"])
                 for row in state["records"] if row.get("visual_job")}
    if scheduled != required:
        failures.append("Not every completed size queued a plot: " +
                        repr(sorted(required - scheduled)))
    for record in state["records"]:
        if "visual_job" not in record:
            continue
        campaign = Path(record["campaign"])
        output = Path(record["visual_output"]) / record["dataset"]
        expected = set()
        for case_file in campaign.glob("cases_*.tsv"):
            with case_file.open(newline="") as handle:
                for row in csv.DictReader(handle, delimiter="\t"):
                    if row["mode"] not in ("pca", "umap", "tsne"):
                        continue
                    views = ("xy", "xz", "yz") if row[
                        "components"] == "3" else ("xy",)
                    expected.update((row["case"], view)
                                    for view in views)
        manifest = output / "visual_manifest.csv"
        if not manifest.is_file():
            failures.append(f"{record['visual_job']}: missing manifest")
            continue
        with manifest.open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        if (len(rows) != len(expected) or
                {(row["case"], row.get("view")) for row in rows} !=
                expected):
            failures.append(f"{record['visual_job']}: case set mismatch")
        for row in rows:
            try:
                count = ROWS[record["phase"]]
                image = output / row["image"]
                if (float(row["rows"]) != count or
                    float(row["plotted_rows"]) != count or
                    row["color_semantics"] != "none" or
                    Path(row["image"]).name != row["image"] or
                    image.is_symlink() or not image.is_file() or
                    image.stat().st_size == 0):
                    raise ValueError("incomplete all-row image")
                checked += 1
            except (KeyError, ValueError, OSError) as error:
                failures.append(f"{record['visual_job']}: {error}")
        failures.extend(figure_failures(
            campaign, output, expected, ROWS[record["phase"]]))
    if not checked:
        failures.append("No all-row images passed validation")
    report = {"status": "PASS" if not failures else "FAIL",
              "images_checked": checked, "failures": failures}
    (root / "visual_audit.json").write_text(
        json.dumps(report, indent=2) + "\n")
    state["visual_status"] = report["status"]
    if failures:
        state["status"] = "VISUAL_FAILURE"
    else:
        state["status"] = ("QUALITY_GAPS" if state["quality_gaps"]
                           else "PASS")
    temporary = root / "state.json.tmp"
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(root / "state.json")
    return report


if __name__ == "__main__":
    result = audit(Path(sys.argv[1]).resolve())
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["status"] == "PASS" else 1)
