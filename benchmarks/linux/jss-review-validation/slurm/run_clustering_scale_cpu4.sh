#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --job-name=feR_JSS_clscale_c
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_clscale_c_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_clscale_c_%j.err
set -euo pipefail
SUITE="${SUITE:-benchmark_scripts/fastembedr_jss_review_validation}"
bash "$SUITE/common/run_clustering_scale_task.sh" cpu
