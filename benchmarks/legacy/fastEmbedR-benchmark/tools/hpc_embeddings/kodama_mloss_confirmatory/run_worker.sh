#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE:?IMAGE is required}"
: "${SCRIPT:?SCRIPT is required}"
: "${OUT_DIR:?OUT_DIR is required}"
mkdir -p "$OUT_DIR"

export OMP_NUM_THREADS="${N_CORES:-1}"
export OPENBLAS_NUM_THREADS="${N_CORES:-1}"
export MKL_NUM_THREADS="${N_CORES:-1}"
export RCPP_PARALLEL_NUM_THREADS="${N_CORES:-1}"
export APPTAINERENV_OMP_NUM_THREADS="$OMP_NUM_THREADS"
export APPTAINERENV_OPENBLAS_NUM_THREADS="$OPENBLAS_NUM_THREADS"
export APPTAINERENV_MKL_NUM_THREADS="$MKL_NUM_THREADS"
export APPTAINERENV_RCPP_PARALLEL_NUM_THREADS="$RCPP_PARALLEL_NUM_THREADS"

GPU_MONITOR_PID=""
cleanup() {
  if [[ -n "$GPU_MONITOR_PID" ]]; then kill "$GPU_MONITOR_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

NV_ARGS=()
if [[ "${BACKEND:-cpu}" == "cuda" ]]; then
  NV_ARGS=(--nv)
  nvidia-smi --query-gpu=timestamp,index,name,utilization.gpu,memory.used,memory.total \
    --format=csv -l 1 > "$OUT_DIR/gpu_memory_trace.csv" 2>&1 &
  GPU_MONITOR_PID=$!
fi

printf 'started=%s\nhost=%s\nscript=%s\n' "$(date --iso-8601=seconds)" "$(hostname)" "$SCRIPT" > "$OUT_DIR/job_identity.txt"
/usr/bin/time -v -o "$OUT_DIR/resource_usage.txt" \
  apptainer exec "${NV_ARGS[@]}" "$IMAGE" Rscript "$SCRIPT" "$@" \
  > "$OUT_DIR/stdout.log" 2> "$OUT_DIR/stderr.log"
printf 'finished=%s\n' "$(date --iso-8601=seconds)" >> "$OUT_DIR/job_identity.txt"

