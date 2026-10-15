#!/usr/bin/env bash
#SBATCH --job-name=feR_deep1b
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_deep1b_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_deep1b_%A_%a.err

set -euo pipefail
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=${DEEP1B_SUITE:-$base/benchmark_scripts/massive-data/deep1b}
bash "$suite/run_case.sh"
