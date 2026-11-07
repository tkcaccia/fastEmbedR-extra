#!/bin/bash
#SBATCH --job-name=fer-fashion-v3-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v2-fashion-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v2-fashion-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v2
test -f "$root/audit_dataset_wave_v3.py"
python3 "$root/audit_dataset_wave_v3.py" --cohort-root "$root" \
  --dataset Fashion-MNIST \
  --jobs 1606419 1606420 1606421 1606422 1606423 1606424 \
  --output "$root/fashion-wave-audit-v3.json"
