#!/usr/bin/env bash
set -euo pipefail

group="${1:?case group required}"
task="${2:-0}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
INPUT_ROOT="${INPUT_ROOT:?input root required}"
OUTPUT_ROOT="${OUTPUT_ROOT:?output root required}"
: "${FASTEMBEDR_DLL_SHA256:?package DLL checksum required}"
source "$SUITE/common/container_runtime.sh"
source "$SUITE/common/campaign_submit.sh"
campaign_verify_suite_revision

case "$group" in
  matched|boundary|recovery)
    mapfile -t ids < <(awk -F, -v group="$group" \
      'NR > 1 && $2 == group {print $1}' \
      "$SUITE/file_backed/cases.csv")
    ids=("${ids[$task]:?invalid task index}")
    ;;
  scaling)
    datasets=(turing deep)
    sizes=(100000 1000000 10000000)
    dataset="${datasets[$((task / 3))]:?invalid task index}"
    rows="${sizes[$((task % 3))]}"
    mapfile -t ids < <(awk -F, -v dataset="$dataset" -v rows="$rows" \
      'NR > 1 && $2 == "scaling" && $3 == dataset && $5 == rows \
      {print $1}' \
      "$SUITE/file_backed/cases.csv")
    ;;
  full_landmark|multi_gpu)
    mapfile -t ids < <(awk -F, -v group="$group" \
      'NR > 1 && $2 == group {print $1}' \
      "$SUITE/file_backed/cases.csv")
    ;;
  *) echo "Unknown file-backed group: $group" >&2; exit 2 ;;
esac
(( ${#ids[@]} > 0 )) || exit 2
runtime="$(command -v apptainer || command -v singularity)"
for id in "${ids[@]}"; do
  seconds=7200
  [[ "$group" != boundary ]] || seconds=43200
  args=(exec --cleanenv --bind "$BASE_DIR:$BASE_DIR")
  if [[ "$group" == scaling || "$group" == full_landmark || \
        "$group" == multi_gpu || \
        ( "$group" == recovery && "$task" == 1 ) ]]; then
    args+=(--nv)
  fi
  echo "Starting file-backed case $id (limit ${seconds}s)"
  backend=cpu
  if [[ "$group" == scaling || "$group" == full_landmark || \
        "$group" == multi_gpu || \
        ( "$group" == recovery && "$task" == 1 ) ]]; then
    backend=cuda
  fi
  export FASTEMBEDR_MONITOR_ALL_GPUS=FALSE
  [[ "$group" != multi_gpu ]] || \
    export FASTEMBEDR_MONITOR_ALL_GPUS=TRUE
  prefix="$OUTPUT_ROOT/file_backed/$id/measurement"
  set +e
  bash "$SUITE/common/run_measured.sh" "$backend" "$prefix" -- \
    timeout --signal=TERM --kill-after=30s "$seconds" \
    "$runtime" "${args[@]}" "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
    "$IMAGE" env \
    "FASTEMBEDR_DLL_SHA256=$FASTEMBEDR_DLL_SHA256" \
    "EXPECTED_VERSION=$EXPECTED_VERSION" \
    "BIGANN_DATA_ROOT=${BIGANN_DATA_ROOT:-$BASE_DIR/Data/BigANN}" \
    "SLURM_MEM_PER_NODE=${SLURM_MEM_PER_NODE:-}" \
    "$FASTEMBEDR_RSCRIPT" "$SUITE/file_backed/run_case.R" \
    "$id" "$INPUT_ROOT" "$OUTPUT_ROOT"
  status=$?
  set -e
  result="$OUTPUT_ROOT/file_backed/$id/result.csv"
  if [[ "$status" -eq 124 || "$status" -eq 137 ]]; then
    python3 "$SUITE/file_backed/write_status.py" \
      "$result" "$id" TIMEOUT "Time limit ${seconds}s exceeded"
  elif [[ ! -f "$result" ]]; then
    python3 "$SUITE/file_backed/write_status.py" \
      "$result" "$id" FAIL "Worker exited $status without a result"
  fi
done
