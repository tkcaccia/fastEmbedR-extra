#!/usr/bin/env bash
#SBATCH --job-name=feR_bigann_data
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=12:00:00
#SBATCH --array=0-1%1
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_bigann_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_bigann_%A_%a.err

set -euo pipefail

case "${SLURM_ARRAY_TASK_ID}" in
    0) dataset=turing ;;
    1) dataset=deep ;;
    *) echo "Unexpected array task" >&2; exit 2 ;;
esac

suite=/scratch/firenze/NN/benchmark_scripts/massive-data
script=$suite/download_bigann_subset.py
root=${BIGANN_DATA_ROOT:-/scratch/firenze/NN/Data/BigANN}
rows=${BIGANN_ROWS:-10000000}
python3 "$script" "$dataset" --rows "$rows" --output-root "$root"
