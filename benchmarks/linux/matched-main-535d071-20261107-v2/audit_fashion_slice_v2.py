"""Independently audit completed COIL20 and Fashion wave cases.

The full cohort may contain simultaneously running cases from other
datasets. Select only the 82 cases explicitly submitted through the two
finished waves, after checking the identity of the complete 462-case plan.
"""

import argparse
from collections import Counter
import json
from pathlib import Path

import audit_scaling as core


def selected_case(case):
    if case["dataset"] == "COIL20":
        return True
    return (case["dataset"] == "Fashion-MNIST" and
            (case["method"] != "PCA" or
             case["cores"] in (4, 8, 16, 32)))


def audit(cohort_root, results, accounting):
    core.HERE = cohort_root
    cases = [json.loads(line) for line in
             (cohort_root / "cases.jsonl").read_text().splitlines()]
    if not core.plan_identity(cases):
        raise ValueError("The complete 462-case plan identity differs")
    selected = [case for case in cases if selected_case(case)]
    if (len(selected) != 82 or
            sum(case["dataset"] == "COIL20" for case in selected) != 42 or
            sum(case["dataset"] == "Fashion-MNIST" for case in selected) != 40 or
            len({case["case_id"] for case in selected}) != 82):
        raise ValueError("The submitted wave's case roster differs")
    jobs = core.accounting(accounting)
    routes_sha = core.sha256(cohort_root / "routes.json")
    worker_sha = core.sha256(cohort_root / "matched_worker.R")
    rows = [core.inspect_case(case, results, jobs, routes_sha, worker_sha)
            for case in selected]
    counts = dict(Counter(row["status"] for row in rows))
    return {"package_commit": core.PACKAGE_COMMIT,
            "audit_scope": "COIL20 all; Fashion except PCA1/PCA2",
            "planned": 82, "counts": counts, "cases": rows,
            "status": "passed" if counts == {"audited": 82} else "failed"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cohort-root", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--accounting", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.cohort_root, args.results, args.accounting)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"],
                      "counts": result["counts"]}, sort_keys=True))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
