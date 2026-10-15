#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:l40s:2
#SBATCH --mem=96G
#SBATCH --time=20:00:00
#SBATCH --job-name=feR_JSS_fb_multi
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_fb_multi_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_fb_multi_%j.err
set -euo pipefail
SUITE="${SUITE:-benchmark_scripts/fastembedr_jss_review_validation}"
bash "$SUITE/file_backed/run_cases.sh" \
  multi_gpu
