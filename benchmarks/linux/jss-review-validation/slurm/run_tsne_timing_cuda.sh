#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --array=0-3%1
#SBATCH --job-name=feR_JSS_tm_g
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_tm_g_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_tm_g_%A_%a.err
set -euo pipefail
TIMING_REPS=10 bash \
  benchmark_scripts/fastembedr_jss_review_validation/common/run_array_task.sh \
  longrun_timing cuda
