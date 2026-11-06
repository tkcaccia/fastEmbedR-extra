#!/bin/bash
#SBATCH --job-name=fer-input-audit-afeaffc
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident_afeaffc_20261106/input-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident_afeaffc_20261106/input-audit-%j.err
set -Eeuo pipefail
cd /scratch/firenze/NN/Data
sha256sum -c /scratch/firenze/NN/benchmarks/resident_afeaffc_20261106/input-SHA256SUMS
