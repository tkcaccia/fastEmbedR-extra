#!/bin/bash
#SBATCH --job-name=fer-v3-mass41-subset-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3/logs/mass41-subset-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3/logs/mass41-subset-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3
cd "$root"
printf '%s  %s\n' \
  eca5563cea06663e712cce90420f610dfebd061eed52b67807162246168bfeb6 \
  audit_mass41_subset_v1.py | sha256sum -c -
python3 "$root/audit_mass41_subset_v1.py" --cohort-root "$root" \
  --job 1607023 --output "$root/mass41-cpu4-subset-audit-v1.json"
