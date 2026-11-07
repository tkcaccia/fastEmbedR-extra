#!/bin/bash
#SBATCH --job-name=fer-v3-coil-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v3-coil-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v3-coil-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3
test -f "$root/audit_single_core_v1.py"
[[ ${PILOT_JOB_ID:?Provide the exact pilot Slurm job ID.} =~ ^[0-9]+$ ]]
python3 "$root/audit_single_core_v1.py" --cohort-root "$root" \
  --dataset COIL20 --cores 4 --job "$PILOT_JOB_ID" \
  --output "$root/coil20-cpu4-pilot-audit.json"
