#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=12
#SBATCH --mem=32G
#SBATCH --time=12:00:00
#SBATCH --array=0-10%11
#SBATCH --job-name=feR_JSS_cmp_in
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_cmp_in_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_cmp_in_%A_%a.err
set -euo pipefail
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_comparator_task.sh \
  inputs
