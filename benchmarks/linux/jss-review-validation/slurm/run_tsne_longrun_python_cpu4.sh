#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=64G
#SBATCH --time=08:00:00
#SBATCH --array=0-31%6
#SBATCH --job-name=feR_JSS_lr_py
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_lr_py_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_lr_py_%A_%a.err
set -euo pipefail
THREADS=4 bash benchmark_scripts/fastembedr_jss_review_validation/common/run_python_longrun_task.sh
