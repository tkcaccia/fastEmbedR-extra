#!/bin/bash
#SBATCH --job-name=fer-535-fashion-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1/fashion-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1/fashion-audit-%j.err
set -Eeuo pipefail
audit=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1
cohort=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v1
expected_auditor=c48f7ab9e45f213be469c9f2131abca57154711eee402ef045d38525525c0325
[[ $(sha256sum "$audit/audit_scaling.py" | cut -d' ' -f1) == "$expected_auditor" ]]
sacct -X -n -P -j 1606232,1606233,1606234,1606235 \
    --format=JobIDRaw,JobName,State,ExitCode > "$audit/accounting-fashion-pca.txt"
set +e
python3 "$audit/audit_scaling.py" \
    --cohort-root "$cohort" --results "$cohort/results" \
    --accounting "$audit/accounting-fashion-pca.txt" \
    --output "$audit/fashion-pca-pilot.json"
audit_exit=$?
set -e
[[ "$audit_exit" -eq 1 ]]
python3 - "$audit/fashion-pca-pilot.json" <<'PY'
import json
import sys

summary = json.load(open(sys.argv[1], encoding="utf-8"))
expected = {"audited": 4, "missing_result": 458}
if summary["counts"] != expected:
    raise SystemExit(f"Unexpected audit counts: {summary['counts']}")
accepted = sorted(case["case_id"] for case in summary["cases"]
                  if case["status"] == "audited")
required = sorted(f"fashion_pca_cpu{cores}_d2_s4_matched_535d071"
                  for cores in (4, 8, 16, 32))
if accepted != required:
    raise SystemExit(f"Unexpected accepted cases: {accepted}")
print("fashion_pca_pilot_audit_passed", ",".join(accepted))
PY
