#!/bin/bash
#SBATCH --job-name=fer-535-fashion-audit-v2
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1/fashion-wave-v2-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1/fashion-wave-v2-%j.err
set -Eeuo pipefail
audit=/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1
cohort=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v1
test "$(sha256sum "$audit/audit_scaling.py" | cut -d' ' -f1)" = \
    c48f7ab9e45f213be469c9f2131abca57154711eee402ef045d38525525c0325
test "$(sha256sum "$audit/audit_fashion_slice_v2.py" | cut -d' ' -f1)" = \
    7eaa0fe2c4c9ca97e241099cac3001f3acac566b3bf9bdf5ccc80d0d593a136d
sacct -X -n -P -j 1606232,1606233,1606234,1606235,1606237,1606239,1606243,1606249,1606252,1606259,1606292,1606293,1606294,1606295,1606296,1606297 \
    --format=JobIDRaw,JobName,State,ExitCode > "$audit/accounting-fashion-v2.txt"
PYTHONPATH="$audit" python3 "$audit/audit_fashion_slice_v2.py" \
    --cohort-root "$cohort" --results "$cohort/results" \
    --accounting "$audit/accounting-fashion-v2.txt" \
    --output "$audit/fashion-wave-v2.json"
