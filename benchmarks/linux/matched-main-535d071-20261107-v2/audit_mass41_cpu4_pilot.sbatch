#!/bin/bash
#SBATCH --job-name=fer-mass41-cpu4-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v2-mass41-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v2-mass41-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v2
test -f "$root/audit_single_core_v1.py"
python3 "$root/audit_single_core_v1.py" --cohort-root "$root" \
  --dataset mass41 --cores 4 --job 1606597 \
  --output "$root/mass41-cpu4-pilot-audit.json"
