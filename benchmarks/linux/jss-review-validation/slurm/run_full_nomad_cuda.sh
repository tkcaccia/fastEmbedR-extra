#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=128G
#SBATCH --time=48:00:00
#SBATCH --array=0-10%2
#SBATCH --job-name=feR_JSS_nomad
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_nomad_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_nomad_%A_%a.err
set -euo pipefail
SUITE="${SUITE:-/scratch/firenze/NN/benchmark_scripts/fastembedr_jss_review_validation}"
COMPARATOR_TASK_ID="${SLURM_ARRAY_TASK_ID:?array task ID required}" \
  FULL_CUDA_PAIR=TRUE \
  bash "$SUITE/common/run_comparator_task.sh" python_nomad
