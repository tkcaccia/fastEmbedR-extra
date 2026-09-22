#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=192G
#SBATCH --time=48:00:00
#SBATCH --array=0-10%4
#SBATCH --job-name=feR_JSS_knno_c
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_knno_c_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_knno_c_%A_%a.err
set -euo pipefail
export MAX_N=2147483647
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_array_task.sh \
  knn_observed cpu
