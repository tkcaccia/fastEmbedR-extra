#!/usr/bin/env bash

set -euo pipefail

BUNDLE="${1:?CUDA bundle name is required}"
TASK_ID="${SLURM_ARRAY_TASK_ID:?Slurm array task ID is required}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"

[[ "$TASK_ID" =~ ^[0-9]+$ ]] || {
  echo "Invalid array task ID: $TASK_ID" >&2
  exit 2
}
case "$BUNDLE" in
  transform_landmark|pca_accuracy) max_task=10 ;;
  tsne_longrun) max_task=3 ;;
  *) echo "Unknown CUDA bundle: $BUNDLE" >&2; exit 2 ;;
esac
(( TASK_ID <= max_task )) || {
  echo "Array task $TASK_ID exceeds $BUNDLE range." >&2
  exit 2
}

STATUS_DIR="$OUTPUT_ROOT/scheduler_status/bundles/$BUNDLE"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/${SLURM_JOB_ID:-local}_${TASK_ID}.csv"
printf 'bundle,dataset_task_id,mode,subtask_id,status,exit_code,elapsed_sec\n' \
  > "$STATUS_FILE"
failures=0

run_one() {
  local mode="$1" subtask="$2" started code status
  local -a command=(env "SLURM_ARRAY_TASK_ID=$subtask")
  [[ "$mode" == landmark_reconstruction ]] && \
    command+=(LANDMARK_FRACTION=0.2)
  [[ "$mode" == longrun_timing ]] && command+=(TIMING_REPS=10)
  started="$(date +%s)"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $BUNDLE $mode task=$subtask"
  if "${command[@]}" bash "$SUITE/common/run_array_task.sh" \
      "$mode" cuda; then
    code=0
    status=completed
  else
    code=$?
    status=failed
    failures=$((failures + 1))
  fi
  printf '%s,%s,%s,%s,%s,%s,%s\n' "$BUNDLE" "$TASK_ID" \
    "$mode" "$subtask" "$status" "$code" \
    "$(( $(date +%s) - started ))" >> "$STATUS_FILE"
}

case "$BUNDLE" in
  transform_landmark|pca_accuracy)
    for ((offset = 0; offset < 2; offset++)); do
      subtask=$((TASK_ID * 2 + offset))
      if [[ "$BUNDLE" == transform_landmark ]]; then
        run_one transform "$subtask"
        run_one landmark_reconstruction "$subtask"
      else
        run_one pca "$subtask"
        run_one pca_accuracy "$subtask"
      fi
    done
    ;;
  tsne_longrun)
    for ((offset = 0; offset < 18; offset++)); do
      run_one longrun "$((TASK_ID * 18 + offset))"
    done
    for ((offset = 0; offset < 2; offset++)); do
      run_one longrun_final "$((TASK_ID * 2 + offset))"
    done
    run_one longrun_timing "$TASK_ID"
    ;;
esac

if (( failures > 0 )); then
  echo "CUDA bundle $BUNDLE task $TASK_ID: $failures failed subruns" >&2
  exit 1
fi
echo "CUDA bundle $BUNDLE task $TASK_ID: all subruns completed"
