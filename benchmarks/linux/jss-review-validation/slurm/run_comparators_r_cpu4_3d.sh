#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=48:00:00
#SBATCH --array=0-76%20
#SBATCH --job-name=feR_JSS_3d_r
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_3d_r_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_3d_r_%A_%a.err
set -euo pipefail
N_COMPONENTS=3 bash \
  benchmark_scripts/fastembedr_jss_review_validation/common/run_comparator_task.sh \
  r_cpu
