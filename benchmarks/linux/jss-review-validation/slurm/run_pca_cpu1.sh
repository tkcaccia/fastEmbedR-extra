#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=48:00:00
#SBATCH --array=0-21%22
#SBATCH --job-name=feR_JSS_p1
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_p1_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_p1_%A_%a.err
set -euo pipefail
export PCA_THREADS_OVERRIDE=1
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_array_task.sh pca cpu
