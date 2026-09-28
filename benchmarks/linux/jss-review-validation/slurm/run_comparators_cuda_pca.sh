#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=3
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --array=0-10%2
#SBATCH --job-name=feR_JSS_pca_g
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_pca_g_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_pca_g_%A_%a.err
set -euo pipefail
export N_COMPONENTS=2
export COMPARATOR_TASK_ID="$((SLURM_ARRAY_TASK_ID * 3))"
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_comparator_task.sh \
  r_cuda
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_comparator_task.sh \
  python_cuda
