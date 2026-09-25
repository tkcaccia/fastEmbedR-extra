#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:20:00
#SBATCH --job-name=feR_JSS_cmp_pc
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_cmp_pc_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_cmp_pc_%j.err
set -euo pipefail
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_comparator_preflight.sh \
  cpu
