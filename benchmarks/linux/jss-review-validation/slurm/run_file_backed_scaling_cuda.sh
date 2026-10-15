#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --array=0-5%2
#SBATCH --job-name=feR_JSS_fb_scale
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_fb_scale_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_fb_scale_%A_%a.err
set -euo pipefail
SUITE="${SUITE:-benchmark_scripts/fastembedr_jss_review_validation}"
bash "$SUITE/file_backed/run_cases.sh" \
  scaling "${SLURM_ARRAY_TASK_ID:-0}"
