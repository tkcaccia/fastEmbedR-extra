#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=16G
#SBATCH --time=48:00:00
#SBATCH --array=0-21%2
#SBATCH --job-name=feR_JSS_3d_g
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_3d_g_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_3d_g_%A_%a.err
set -euo pipefail
N_COMPONENTS=3 bash \
  benchmark_scripts/fastembedr_jss_review_validation/common/run_comparator_task.sh \
  python_cuda
