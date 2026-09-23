#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --array=0-71%5
#SBATCH --job-name=feR_JSS_lr_g
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_lr_g_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_lr_g_%A_%a.err
set -euo pipefail
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_array_task.sh longrun cuda
