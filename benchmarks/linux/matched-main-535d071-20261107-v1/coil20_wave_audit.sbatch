#!/bin/bash
#SBATCH --job-name=fer-535-coil-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1/coil20-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1/coil20-audit-%j.err
set -Eeuo pipefail
audit=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1
cohort=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v1
expected_auditor=c48f7ab9e45f213be469c9f2131abca57154711eee402ef045d38525525c0325
[[ $(sha256sum "$audit/audit_scaling.py" | cut -d' ' -f1) == "$expected_auditor" ]]
sacct -X -n -P -j 1606232,1606233,1606234,1606235,1606237,1606239,1606243,1606249,1606252,1606259 \
    --format=JobIDRaw,JobName,State,ExitCode > "$audit/accounting-coil20-wave.txt"
set +e
python3 "$audit/audit_scaling.py" \
    --cohort-root "$cohort" --results "$cohort/results" \
    --accounting "$audit/accounting-coil20-wave.txt" \
    --output "$audit/coil20-wave.json"
audit_exit=$?
set -e
[[ "$audit_exit" -eq 1 ]]
python3 - "$audit/coil20-wave.json" <<'PY'
import json
import sys

summary = json.load(open(sys.argv[1], encoding="utf-8"))
if summary["counts"] != {"audited": 46, "missing_result": 416}:
    raise SystemExit(f"Unexpected audit counts: {summary['counts']}")
accepted = [case["case_id"] for case in summary["cases"]
            if case["status"] == "audited"]
coil = [case for case in accepted if case.startswith("coil20_")]
fashion = [case for case in accepted if case.startswith("fashion_pca_")]
if len(coil) != 42 or len(fashion) != 4:
    raise SystemExit(f"Unexpected accepted cases: COIL20={len(coil)}, Fashion={len(fashion)}")
print("coil20_wave_audit_passed", len(coil), len(fashion))
PY
