#!/bin/bash
#SBATCH --job-name=fer-coil-v3-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v2-coil-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v2-coil-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v2
test -f "$root/audit_dataset_wave_v3.py"
python3 "$root/audit_dataset_wave_v3.py" --cohort-root "$root" \
  --dataset COIL20 --jobs 1606375 1606376 1606377 1606378 1606379 1606380 \
  --output "$root/coil20-wave-audit-v3.json"
