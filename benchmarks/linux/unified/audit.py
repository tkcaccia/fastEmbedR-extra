#!/usr/bin/env python3
"""Audit the three source-locked components of one manuscript campaign."""

import argparse
import csv
import json
from collections import Counter
from pathlib import Path


COMPONENTS = ("jss_paired", "jss_extended", "deep1b_matrix")
RANK = {"PASS": 0, "WARN": 1, "INCOMPLETE": 2, "FAIL": 3}


def rows(path):
    if not path.is_file():
        return []
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def properties(path):
    if not path.is_file():
        return {}
    return dict(line.strip().split("=", 1) for line in
                path.read_text().splitlines() if "=" in line)


def result(status, detail):
    return {"status": status, "detail": detail}


def jss_status(path, digest):
    if not path.is_dir():
        return result("INCOMPLETE", "campaign directory not created")
    launch = properties(path / "launch_status.txt")
    if launch.get("status") == "FAILED":
        return result("FAIL", "JSS launch failed")
    manifest = properties(path / "campaign_manifest.txt")
    if manifest and manifest.get("image_sha256") != digest:
        return result("FAIL", "JSS image identity differs")
    failures = rows(path / "failures.tsv")
    audit = path / "final_audit.txt"
    if audit.is_file():
        content = audit.read_text().splitlines()
        verdict = properties(audit).get("status")
        if not verdict:
            verdict = content[0].strip() if content else ""
        if verdict not in ("PASS", "WARN") or failures:
            return result("FAIL", "JSS final audit or worker tasks failed")
        if not manifest or launch.get("status") != "SUBMITTED":
            return result("FAIL", "JSS provenance is incomplete")
        if verdict == "WARN":
            return result("WARN", "measured comparator warning")
        return result("PASS", "final audit passed")
    if failures:
        return result("FAIL", f"{len(failures)} failed worker tasks")
    return result("INCOMPLETE", "final JSS audit not available")


def deep_status(ledger, digest):
    cases = []
    if not ledger.is_file():
        return result("INCOMPLETE", "matrix ledger not available"), cases
    root = ledger.parent
    identity = properties(root / "identity.txt")
    if identity.get("image_sha256") != digest:
        return result("FAIL", "Deep1B image identity differs"), cases
    plan = rows(root / "plan.tsv")
    jobs = rows(ledger)
    if not plan or not jobs or not (root / "source.sha256").is_file():
        return result("INCOMPLETE", "plan, jobs, or source lock missing"), cases
    planned = {(r["mode"], r["rows"], r["lane"]) for r in plan}
    submitted = [(r["mode"], r["rows"], r["lane"]) for r in jobs]
    if len(submitted) != len(set(submitted)) or set(submitted) - planned:
        return result("FAIL", "duplicate or unplanned matrix cases"), cases
    for job in jobs:
        case = {key: job[key] for key in ("mode", "rows", "lane", "job")}
        audit = Path(job["campaign"]) / "audit.json"
        if not audit.is_file():
            case.update(status="INCOMPLETE", detail="case audit missing")
        else:
            try:
                evidence = json.loads(audit.read_text())
            except (OSError, ValueError):
                case.update(status="FAIL", detail="invalid case audit")
            else:
                verdict = evidence.get("status")
                warnings = evidence.get("warnings") or []
                if verdict == "PASS" and warnings:
                    case.update(status="WARN", detail="; ".join(warnings))
                elif verdict == "PASS":
                    case.update(status="PASS", detail="audit passed")
                else:
                    case.update(status="FAIL", detail=str(evidence.get(
                        "failures", [f"audit status: {verdict}"])))
        cases.append(case)
    missing = len(planned - set(submitted))
    statuses = [case["status"] for case in cases]
    if missing:
        statuses.append("INCOMPLETE")
    verdict = max(statuses, key=RANK.get)
    detail = f"{len(cases)}/{len(planned)} submitted; "
    detail += ", ".join(f"{key}={value}" for key, value in
                        sorted(Counter(statuses).items()))
    return result(verdict, detail), cases


def evaluate(root):
    identity = root / "image.sha256"
    if not identity.is_file():
        raise ValueError("Unified image identity is missing")
    digest = identity.read_text().split()[0]
    manifest = rows(root / "components.tsv")
    if len(manifest) != len(COMPONENTS) or {
            r.get("component") for r in manifest} != set(COMPONENTS):
        raise ValueError("Unified component manifest is incomplete")
    launch = rows(root / "launch_status.tsv")
    launches = {r["campaign"]: r for r in launch}
    outcomes = {}
    cases = []
    for component in COMPONENTS:
        path = next(r["path"] for r in manifest if
                    r["component"] == component)
        if not path:
            outcomes[component] = result("FAIL", "component path missing")
        elif component == "deep1b_matrix":
            outcomes[component], cases = deep_status(Path(path), digest)
        else:
            outcomes[component] = jss_status(Path(path), digest)
    for component, stage in (("jss_paired", "jss_staged"),
                             ("jss_extended", "jss_staged"),
                             ("deep1b_matrix", "deep1b")):
        if stage in launches and launches[stage]["launch_exit_code"] != "0":
            outcomes[component] = result("FAIL", "component launch failed")
    if not launches:
        outcomes["launch"] = result("INCOMPLETE", "launch record missing")
    status = max((item["status"] for item in outcomes.values()),
                 key=RANK.get)
    return {"status": status, "image_sha256": digest,
            "components": outcomes, "cases": cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Unified run directory")
    parser.add_argument("--write", action="store_true",
                        help="Write aggregate audit files beside the ledgers")
    args = parser.parse_args()
    try:
        report = evaluate(args.root)
    except (OSError, ValueError, KeyError) as exc:
        parser.error(str(exc))
    if args.write:
        (args.root / "audit.json").write_text(
            json.dumps(report, indent=2) + "\n")
        with (args.root / "audit_cases.tsv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, delimiter="\t",
                                    fieldnames=("mode", "rows", "lane", "job",
                                                "status", "detail"))
            writer.writeheader()
            writer.writerows(report["cases"])
    print(report["status"])
    for name, item in report["components"].items():
        print(f"{name}: {item['status']} - {item['detail']}")
    raise SystemExit(0 if report["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
