#!/usr/bin/env bash

set -euo pipefail
BACKEND="${1:?backend is required}"
[[ "$BACKEND" == cpu || "$BACKEND" == cuda ]] || {
  echo "HPC clustering scale supports cpu or cuda." >&2
  exit 2
}
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
OUTPUT_ROOT="${OUTPUT_ROOT:?OUTPUT_ROOT is required}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
CONTAINER="$(command -v apptainer || command -v singularity || true)"
[[ -n "$CONTAINER" && -f "$IMAGE" ]] || {
  echo "Container runtime or benchmark image is missing." >&2
  exit 1
}
source "$SUITE/common/container_runtime.sh"
source "$SUITE/common/campaign_submit.sh"
campaign_verify_suite_revision
OUT="$OUTPUT_ROOT/clustering_scale/$BACKEND"
PREFIX="$OUTPUT_ROOT/measurement/clustering_scale/$BACKEND"
mkdir -p "$OUT" "$PREFIX"
NV=()
if [[ "$BACKEND" == cuda ]]; then NV=(--nv); fi
COMMAND=(
  "$CONTAINER" exec "${NV[@]}" --cleanenv
  --bind "$BASE_DIR:$BASE_DIR" --pwd "$BASE_DIR"
  "${FASTEMBEDR_CONTAINER_R_ENV[@]}"
  --env "OMP_NUM_THREADS=1"
  --env "OPENBLAS_NUM_THREADS=1"
  "$IMAGE" "$FASTEMBEDR_RSCRIPT"
  "$SUITE/common/run_clustering_scale.R"
  "$BACKEND" "$OUT/clustering_scale.csv" "$EXPECTED_VERSION"
)
if bash "$SUITE/common/run_measured.sh" "$BACKEND" \
    "$PREFIX/${SLURM_JOB_ID:-local}" -- "${COMMAND[@]}"; then
  printf 'backend,status\n%s,success\n' "$BACKEND" > "$OUT/status.csv"
else
  code="$?"
  printf 'backend,status,exit_code\n%s,failed,%s\n' \
    "$BACKEND" "$code" > "$OUT/status.csv"
  exit "$code"
fi
