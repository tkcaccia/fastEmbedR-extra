#!/usr/bin/env bash
#SBATCH --job-name=feR_unified_launch
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_unified_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_unified_%j.err
set -euo pipefail

base=${FASTEMBEDR_BASE:-/scratch/firenze/NN}
bash "$base/benchmark_scripts/unified/launch.sh"
