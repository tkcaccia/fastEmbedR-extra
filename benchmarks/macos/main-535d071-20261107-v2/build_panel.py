#!/usr/bin/env python3
"""Replan the reviewed 693-case resident Mac cohort for package 535d071."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from policy import valid_case


HERE = Path(__file__).resolve().parent
PREVIOUS = HERE.parent / "main-afeaffc-20261106"
COMMIT = "535d071849945db3fa550d3c50f80633b91748cc"
SOURCE = "/Users/silvanopiazza/Documents/Stefano/fastEmbedR-release-535d071-20261107"
ROOT = "/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-535d071-benchmark-v2-20261107"
METHOD_DIMS = {("PCA", 2), ("t-SNE", 2), ("t-SNE", 3),
               ("UMAP", 2), ("UMAP", 3), ("Leiden", 0),
               ("Louvain", 0)}


def read_cases():
    return [json.loads(line) for line in
            (PREVIOUS / "cases.jsonl").read_text().splitlines()]


def build(source_sha, dll_sha):
    old = read_cases()
    inventory = json.loads((HERE / "dataset-inventory.json").read_text())
    if len(old) != 693 or len(inventory) != 11:
        raise ValueError("Previous panel or dataset inventory is incomplete")
    names = [row["case_id"] for row in old]
    if len(set(names)) != len(names) or not all(
            name.endswith("afeaffc") for name in names):
        raise ValueError("Previous case IDs are not unique/source-locked")
    queue_old = (PREVIOUS / "queue.txt").read_text().splitlines()
    queue_ids = [Path(name).stem for name in queue_old]
    if len(queue_ids) != 691 or set(queue_ids) != set(names[2:]) or \
            set(names[:2]) & set(queue_ids):
        raise ValueError("Previous queue does not cover the remaining cases")
    cases = []
    for original in old:
        case = dict(original)
        row = inventory[case["dataset"]]
        for key in ("input_path", "input_sha256", "expected_rows",
                    "expected_columns"):
            if case[key] != row[key]:
                raise ValueError("Input inventory mismatch: " + case["case_id"])
        case["case_id"] = case["case_id"].removesuffix("afeaffc") + "535d071_v2"
        case["source_dir"] = SOURCE
        case["source_sha256"] = source_sha
        case["dll_sha256"] = dll_sha
        case["output_dir"] = ROOT + "/results/" + case["case_id"]
        if (case["method"] == "t-SNE" and case["dimensions"] == 3 and
                case["expected_rows"] >= 500000):
            case["timeout_seconds"] = 7200
        if not valid_case(case):
            raise ValueError("New case violates policy: " + case["case_id"])
        cases.append(case)
    cohorts = Counter((c["dataset"], c["method"], c["dimensions"],
                       c["backend"], c["cores"]) for c in cases)
    if len(cohorts) != 231 or set(cohorts.values()) != {3}:
        raise ValueError("Unbalanced dataset/method/hardware panel")
    for dataset in inventory:
        expected = {(dataset, method, dim, backend, cores)
                    for method, dim in METHOD_DIMS
                    for backend, cores in (("cpu", 1), ("cpu", 4),
                                           ("metal", 1))}
        if not expected.issubset(cohorts):
            raise ValueError("Missing route: " + dataset)
    return cases


def write(cases):
    manifests = HERE / "manifests"
    manifests.mkdir(exist_ok=True)
    ordered_names = []
    for case in cases:
        name = case["case_id"] + ".json"
        (manifests / name).write_text(json.dumps(case, sort_keys=True) + "\n")
        ordered_names.append(name)
    old_queue = (PREVIOUS / "queue.txt").read_text().splitlines()
    order = ordered_names[:2] + [name.replace("afeaffc", "535d071_v2")
                                 for name in old_queue]
    if len(order) != 693 or set(order) != set(ordered_names):
        raise ValueError("New queue does not cover exactly 693 cases")
    (HERE / "queue.txt").write_text("\n".join(order) + "\n")
    lines = "\n".join(json.dumps(case, sort_keys=True) for case in cases) + "\n"
    (HERE / "cases.jsonl").write_text(lines)
    summary = {"package_commit": COMMIT, "cases": len(cases),
               "queued": len(order), "precompleted": 0,
               "storage_mode": "resident", "fit_scope": "full",
               "source_sha256": cases[0]["source_sha256"],
               "dll_sha256": cases[0]["dll_sha256"],
               "cases_sha256": hashlib.sha256(lines.encode()).hexdigest(),
               "scope": "11 datasets, seven methods/dimensions, three seeds, CPU1/CPU4/Metal1",
               "excluded": ["file-backed", "landmark", "competitors", "Deep1B"]}
    (HERE / "plan-summary.json").write_text(
        json.dumps(summary, indent=2) + "\n")
    pilot = dict(cases[0])
    pilot["case_id"] += "_pilot"
    pilot["output_dir"] = ROOT + "/pilot-results/" + pilot["case_id"]
    if not valid_case(pilot):
        raise ValueError("Pilot case violates policy")
    (HERE / "pilot-case.json").write_text(
        json.dumps(pilot, sort_keys=True) + "\n")
    print(json.dumps(summary, sort_keys=True))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--dll-sha", required=True)
    args = parser.parse_args()
    if any(len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value)
           for value in (args.source_sha, args.dll_sha)):
        parser.error("SHA-256 values must be lowercase hex")
    write(build(args.source_sha, args.dll_sha))


if __name__ == "__main__":
    main()
