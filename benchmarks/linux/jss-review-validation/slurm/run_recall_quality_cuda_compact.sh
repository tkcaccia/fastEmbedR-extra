#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --array=0-10%5
#SBATCH --job-name=feR_JSS_rq_g
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_rq_g_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_rq_g_%A_%a.err

set -uo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation"
DATASET_TASK_ID="${SLURM_ARRAY_TASK_ID:?missing Slurm array task ID}"
FAILURES=0

run_case() {
  local label="$1"
  shift
  echo "[$(date --iso-8601=seconds)] starting $label"
  if "$@"; then
    echo "[$(date --iso-8601=seconds)] completed $label"
  else
    local code=$?
    FAILURES=$((FAILURES + 1))
    echo "[$(date --iso-8601=seconds)] failed $label exit=$code" >&2
  fi
}

run_case "observed KNN recall" env \
  SLURM_ARRAY_TASK_ID="$DATASET_TASK_ID" \
  MAX_N=2147483647 \
  bash "$SUITE/common/run_array_task.sh" knn_observed cuda

for QUALITY_OFFSET in $(seq 0 11); do
  QUALITY_TASK_ID=$((DATASET_TASK_ID * 12 + QUALITY_OFFSET))
  run_case "backend quality configuration $QUALITY_OFFSET" env \
    SLURM_ARRAY_TASK_ID="$QUALITY_TASK_ID" \
    MAX_N=70000 \
    bash "$SUITE/common/run_array_task.sh" backend_quality cuda
done

if [[ "$FAILURES" -gt 0 ]]; then
  echo "Completed dataset task with $FAILURES failed subruns." >&2
  exit 1
fi

echo "Completed dataset task without failures."
