#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --job-name=feR_JSS_fb_audit
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_fb_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_fb_audit_%j.err
set -euo pipefail
SUITE="${SUITE:-benchmark_scripts/fastembedr_jss_review_validation}"
python3 "$SUITE/file_backed/audit.py" "${OUTPUT_ROOT:?}"
