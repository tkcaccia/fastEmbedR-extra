#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --array=0-3%2
#SBATCH --job-name=feR_JSS_tm_py
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_tm_py_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_tm_py_%A_%a.err
set -euo pipefail
THREADS=4 TIMING_REPS=5 bash \
  benchmark_scripts/fastembedr_jss_review_validation/common/run_python_timing_task.sh
