#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
INPUT_ROOT="${INPUT_ROOT:-$BASE_DIR/fastEmbedR-input/jss_validation}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
TASK_ID="${SLURM_ARRAY_TASK_ID:-0}"
THREADS="${THREADS:-4}"
TIMING_REPS="${TIMING_REPS:-5}"
CONTAINER="$(command -v apptainer || command -v singularity || true)"
DATASETS=(USPS FashionMNIST MNIST MetRef)

source "$SUITE/common/container_runtime.sh"

[[ -n "$CONTAINER" ]] || {
  echo "apptainer/singularity not found" >&2
  exit 1
}
[[ -f "$IMAGE" ]] || { echo "missing image: $IMAGE" >&2; exit 1; }

DATASET="${DATASETS[$TASK_ID]}"
INPUT_DIR="$INPUT_ROOT/$DATASET/tsne_longrun_portable"
OUTPUT_DIR="$OUTPUT_ROOT/tsne_longrun_timing/$DATASET/python_cpu_4t"
MEASURE_DIR="$OUTPUT_ROOT/measurement/tsne_timing_python/$DATASET"
PREFIX="$MEASURE_DIR/${SLURM_JOB_ID:-local}_${TASK_ID}"
mkdir -p "$OUTPUT_DIR" "$MEASURE_DIR" "$BASE_DIR/benchmark_logs"

COMMAND=(
  "$CONTAINER" exec --cleanenv
  --bind "$BASE_DIR:$BASE_DIR"
  --pwd "$BASE_DIR"
  "${FASTEMBEDR_CONTAINER_BASE_ENV[@]}"
  --env "OMP_NUM_THREADS=$THREADS"
  --env "OPENBLAS_NUM_THREADS=$THREADS"
  --env "MKL_NUM_THREADS=$THREADS"
  "$IMAGE" "$FASTEMBEDR_PYTHON"
  "$SUITE/common/run_python_tsne_longrun.py"
  "--input-dir=$INPUT_DIR"
  "--output-dir=$OUTPUT_DIR"
  "--dataset=$DATASET"
  "--seed=4"
  "--normal-iterations=750"
  "--threads=$THREADS"
  "--timing-reps=$TIMING_REPS"
  --warmup
)

echo "[$(date --iso-8601=seconds)] Python timing dataset=$DATASET"
bash "$SUITE/common/run_measured.sh" cpu "$PREFIX" -- "${COMMAND[@]}"
