#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=3
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=16G
#SBATCH --time=00:20:00
#SBATCH --job-name=feR_JSS_cmp_pg
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_cmp_pg_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_cmp_pg_%j.err
set -euo pipefail
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_comparator_preflight.sh \
  cuda
