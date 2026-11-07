#!/bin/bash
#SBATCH --job-name=fer-pca-shape-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v2-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v2-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v2
test -f "$root/audit_scaling.py"
test -f "$root/audit_pca_shape_pilot.py"
python3 "$root/audit_pca_shape_pilot.py" "$root" \
  "$root/pca-shape-pilot-audit.json"
