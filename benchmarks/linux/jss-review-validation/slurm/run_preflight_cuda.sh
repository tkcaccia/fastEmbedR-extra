#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --job-name=feR_JSS_pre_gpu
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_pre_gpu_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_pre_gpu_%j.err
set -euo pipefail
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_array_task.sh preflight cuda
