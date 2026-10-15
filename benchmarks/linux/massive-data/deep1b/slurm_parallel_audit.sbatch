#!/usr/bin/env bash
#SBATCH --job-name=feR_bigann_audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:45:00
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_bigann_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_bigann_audit_%j.err

set -euo pipefail
base=${DEEP1B_BASE:-/scratch/firenze/NN}
bash "$base/benchmark_scripts/massive-data/deep1b/audit_parallel.sh"
