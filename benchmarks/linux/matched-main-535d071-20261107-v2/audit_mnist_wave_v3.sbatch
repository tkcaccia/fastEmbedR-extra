#!/bin/bash
#SBATCH --job-name=fer-mnist-v3-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v2-mnist-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v2-mnist-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v2
test -f "$root/audit_dataset_wave_v3.py"
python3 "$root/audit_dataset_wave_v3.py" --cohort-root "$root" \
  --dataset MNIST --jobs 1606549 1606550 1606551 1606552 1606553 1606554 \
  --output "$root/mnist-wave-audit-v3.json"
