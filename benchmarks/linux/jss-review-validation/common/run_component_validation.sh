#!/usr/bin/env bash

set -euo pipefail

BACKEND="${1:?backend is required}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
CONTAINER="$(command -v apptainer || command -v singularity || true)"
OUT="$OUTPUT_ROOT/component_validation/$BACKEND"
PREFIX="$OUT/${SLURM_JOB_ID:-local}"
STATUS_FILE="$OUT/${SLURM_JOB_ID:-local}.scheduler_status.csv"

mkdir -p "$OUT" "$BASE_DIR/benchmark_logs"
[[ -n "$CONTAINER" ]] || { echo "apptainer/singularity not found" >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "missing image: $IMAGE" >&2; exit 1; }

source "$SUITE/common/container_runtime.sh"

NV=()
REQUESTED=cpu
if [[ "$BACKEND" == "cuda" ]]; then
  NV=(--nv)
  REQUESTED=cpu,cuda
fi

COMMAND=(
  "$CONTAINER" exec "${NV[@]}" --cleanenv
  --bind "$BASE_DIR:$BASE_DIR"
  --pwd "$BASE_DIR"
  "${FASTEMBEDR_CONTAINER_R_ENV[@]}"
  "$IMAGE" "$FASTEMBEDR_RSCRIPT"
  "$SUITE/component_source/tools/validate_tsne_numerics.R"
  "--source-root=$SUITE/component_source"
  "--out-dir=$OUT/results"
  "--backends=$REQUESTED"
)

record_status() {
  printf 'backend,job_id,status,exit_code\n' > "$STATUS_FILE"
  printf '%s,%s,%s,%s\n' "$BACKEND" "${SLURM_JOB_ID:-local}" "$1" "$2" \
    >> "$STATUS_FILE"
}
trap 'record_status terminated 143; exit 143' TERM
trap 'record_status interrupted 130; exit 130' INT
set +e
bash "$SUITE/common/run_measured.sh" "$BACKEND" "$PREFIX" -- "${COMMAND[@]}"
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  record_status completed 0
else
  record_status failed "$STATUS"
fi
exit "$STATUS"
