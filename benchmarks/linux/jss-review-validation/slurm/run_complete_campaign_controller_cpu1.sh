#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=48:00:00
#SBATCH --job-name=feR_JSS_ctl
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_ctl_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_ctl_%j.err

set -euo pipefail
bash \
  benchmark_scripts/fastembedr_jss_review_validation/common/run_complete_campaign_controller.sh
