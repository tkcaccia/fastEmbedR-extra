#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --job-name=feR_JSS_num_g
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_num_g_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_num_g_%j.err
set -euo pipefail
bash benchmark_scripts/fastembedr_jss_review_validation/common/run_component_validation.sh cuda
