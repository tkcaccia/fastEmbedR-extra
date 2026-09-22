#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation"
cd "$BASE_DIR"
mkdir -p benchmark_logs fastEmbedR-input/jss_validation \
  fastEmbedR-results/jss_validation

bash "$SUITE/verify_preflight.sh"

submit() {
  local dependency="$1"
  local script="$2"
  if [[ -n "$dependency" ]]; then
    sbatch --parsable --dependency="$dependency" "$script"
  else
    sbatch --parsable "$script"
  fi
}

PRECOMPUTE="$(submit '' "$SUITE/slurm/run_precompute_cpu12.sh")"
CPU_JOB="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_recall_quality_cpu4_compact.sh")"
CUDA_JOB="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_recall_quality_cuda_compact.sh")"
AGGREGATE="$(submit "afterany:$CPU_JOB:$CUDA_JOB" \
  "$SUITE/slurm/run_aggregate_cpu1.sh")"

cat <<EOF
Submitted compact recall and backend-quality validation.
  preflight gate: passed before submission
  precompute:     $PRECOMPUTE
  CPU datasets:   $CPU_JOB
  CUDA datasets:  $CUDA_JOB
  aggregate:      $AGGREGATE
EOF
