#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:20:00
#SBATCH --job-name=feR_JSS_image
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_image_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_image_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"

cd "$BASE_DIR"
bash "$SUITE/verify_preflight.sh"
bash "$SUITE/submit_complete_campaign.sh"
