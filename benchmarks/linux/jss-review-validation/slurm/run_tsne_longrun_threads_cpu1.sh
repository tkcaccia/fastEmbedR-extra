#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --array=0-11%11
#SBATCH --job-name=feR_JSS_lr1
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_lr1_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_lr1_%A_%a.err
set -euo pipefail
export LONGRUN_THREADS_OVERRIDE=1
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_array_task.sh longrun_threads cpu
