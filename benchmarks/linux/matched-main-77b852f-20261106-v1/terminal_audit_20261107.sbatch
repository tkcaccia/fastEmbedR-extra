#!/bin/bash
#SBATCH --job-name=fer-fashion-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/audit_matched_77b852f_20261106_v1/fashion-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/audit_matched_77b852f_20261106_v1/fashion-audit-%j.err
set -Eeuo pipefail
audit=/scratch/firenze/NN/benchmarks/audit_matched_77b852f_20261106_v1
cohort=/scratch/firenze/NN/benchmarks/matched_main_77b852f_20261106_v1
expected_auditor=ae9ba4cf0087474de43168b4161739d2075f053562438248976e555da0492a8c
[[ $(sha256sum "$audit/audit_scaling.py" | cut -d' ' -f1) == "$expected_auditor" ]]
sacct -X -n -P \
    -j 1605329,1605330,1605331,1605332,1605333,1605334,1605376,1605377,1605378,1605379,1605380,1605381 \
    --format=JobIDRaw,JobName,State,ExitCode > "$audit/accounting-fashion-20261107.txt"
set +e
python3 "$audit/audit_scaling.py" \
    --cohort-root "$cohort" --results "$cohort/results" \
    --accounting "$audit/accounting-fashion-20261107.txt" \
    --output "$audit/audit-fashion-20261107.json"
audit_exit=$?
set -e
[[ "$audit_exit" -eq 1 ]]
python3 - "$audit/audit-fashion-20261107.json" <<'PY'
import json
import sys
from collections import Counter

summary = json.load(open(sys.argv[1], encoding="utf-8"))
expected = {"audited": 80, "failed_case": 4, "missing_result": 378}
if summary["counts"] != expected:
    raise SystemExit(f"Unexpected audit counts: {summary['counts']}")
failed = sorted(case["case_id"] for case in summary["cases"]
                if case["status"] == "failed_case")
expected_failed = [f"fashion_pca_cpu{cores}_d2_s4_matched_77b852f"
                   for cores in (4, 8, 16, 32)]
if failed != sorted(expected_failed):
    raise SystemExit(f"Unexpected failed cases: {failed}")
print("terminal_audit_passed", Counter(case["status"]
                                       for case in summary["cases"]))
print("failed_cases", ",".join(failed))
PY
