#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --job-name=feR_JSS_fb_recover_gpu
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_fb_recover_gpu_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_fb_recover_gpu_%j.err
set -euo pipefail
SUITE="${SUITE:-benchmark_scripts/fastembedr_jss_review_validation}"
bash "$SUITE/file_backed/run_cases.sh" \
  recovery 1
