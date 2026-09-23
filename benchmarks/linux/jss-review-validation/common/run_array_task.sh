#!/usr/bin/env bash

set -euo pipefail

MODE="${1:?mode is required}"
BACKEND="${2:?backend is required}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
DATA_ROOT="${DATA_ROOT:-$BASE_DIR/Data}"
INPUT_ROOT="${INPUT_ROOT:-$BASE_DIR/fastEmbedR-input/jss_validation}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
TASK_ID="${SLURM_ARRAY_TASK_ID:-0}"
CONTAINER="$(command -v apptainer || command -v singularity || true)"

source "$SUITE/common/container_runtime.sh"

IMAGE_SHA256="${FASTEMBEDR_IMAGE_SHA256:-}"
if [[ "$MODE" == "preflight" && -z "$IMAGE_SHA256" ]]; then
  if command -v sha256sum >/dev/null 2>&1; then
    IMAGE_SHA256="$(sha256sum "$IMAGE" | awk '{print $1}')"
  else
    IMAGE_SHA256="$(shasum -a 256 "$IMAGE" | awk '{print $1}')"
  fi
fi

DATASETS=(
  COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST
  imagenet MetRef mass41 TabulaMuris Macosko2015_retina
)
SUPPORTS=(1 3)
METHODS=(tsne umap)
THREADS=(1 2 4 8 12)
PCA_THREADS=(1 4 12)
PCA_RANKS=(2 50)
SCALING_DATASETS=(COIL20 MNIST flow18 imagenet)
LONGRUN_DATASETS=(USPS FashionMNIST MNIST MetRef)
LONGRUN_GRIDS=(128 256 512)
LONGRUN_ITERATIONS=(50 100 250 500 750 1000)
LONGRUN_SEEDS=(4 17 42)
LONGRUN_FINAL_SEEDS=(4 17)
LONGRUN_THREAD_COUNTS=(1 12)
QUALITY_METHODS=(tsne umap)
QUALITY_BOUNDARIES=(matched_knn full_workflow)
QUALITY_SEEDS=(4 17 42)

[[ -n "$CONTAINER" ]] || { echo "apptainer/singularity not found" >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "missing image: $IMAGE" >&2; exit 1; }
[[ -f "$SUITE/common/run_validation.R" ]] || {
  echo "missing validation driver: $SUITE/common/run_validation.R" >&2
  exit 1
}

DATASET=all
THREAD_COUNT=4
EXTRA=()
case "$MODE" in
  preflight)
    THREAD_COUNT=1
    ;;
  precompute|affinity|knn_observed|knn_sensitivity)
    DATASET="${DATASETS[$TASK_ID]}"
    [[ "$MODE" == "precompute" || "$MODE" == "affinity" ]] && THREAD_COUNT=12
    ;;
  longrun_precompute)
    DATASET="${LONGRUN_DATASETS[$TASK_ID]}"
    THREAD_COUNT=12
    ;;
  longrun)
    DATASET_INDEX=$((TASK_ID / 18))
    REMAINDER=$((TASK_ID % 18))
    GRID="${LONGRUN_GRIDS[$((REMAINDER / 6))]}"
    ITERATIONS="${LONGRUN_ITERATIONS[$((REMAINDER % 6))]}"
    DATASET="${LONGRUN_DATASETS[$DATASET_INDEX]}"
    THREAD_COUNT=4
    EXTRA+=("--grid-size=$GRID" "--normal-iterations=$ITERATIONS")
    EXTRA+=("--run-seed=42")
    ;;
  longrun_final)
    DATASET_INDEX=$((TASK_ID / 2))
    SEED="${LONGRUN_FINAL_SEEDS[$((TASK_ID % 2))]}"
    DATASET="${LONGRUN_DATASETS[$DATASET_INDEX]}"
    THREAD_COUNT=4
    EXTRA+=("--grid-size=256" "--normal-iterations=750")
    EXTRA+=("--run-seed=$SEED")
    MODE=longrun
    ;;
  longrun_timing)
    DATASET="${LONGRUN_DATASETS[$TASK_ID]}"
    THREAD_COUNT=4
    EXTRA+=("--grid-size=256" "--normal-iterations=750")
    EXTRA+=("--run-seed=4")
    ;;
  longrun_threads)
    [[ "$BACKEND" == "cpu" ]] || {
      echo "longrun_threads is CPU-only" >&2
      exit 2
    }
    if [[ -n "${LONGRUN_THREADS_OVERRIDE:-}" ]]; then
      DATASET_INDEX=$((TASK_ID / 3))
      REMAINDER=$((TASK_ID % 3))
      THREAD_COUNT="$LONGRUN_THREADS_OVERRIDE"
      SEED="${LONGRUN_SEEDS[$REMAINDER]}"
    else
      DATASET_INDEX=$((TASK_ID / 6))
      REMAINDER=$((TASK_ID % 6))
      THREAD_COUNT="${LONGRUN_THREAD_COUNTS[$((REMAINDER / 3))]}"
      SEED="${LONGRUN_SEEDS[$((REMAINDER % 3))]}"
    fi
    DATASET="${LONGRUN_DATASETS[$DATASET_INDEX]}"
    EXTRA+=("--grid-size=256" "--normal-iterations=750")
    EXTRA+=("--run-seed=$SEED")
    MODE=longrun
    ;;
  support)
    DATASET="${DATASETS[$((TASK_ID / 2))]}"
    SUPPORT="${SUPPORTS[$((TASK_ID % 2))]}"
    EXTRA+=("--support-multiplier=$SUPPORT")
    ;;
  backend_quality)
    DATASET_INDEX=$((TASK_ID / 12))
    REMAINDER=$((TASK_ID % 12))
    BOUNDARY="${QUALITY_BOUNDARIES[$((REMAINDER / 6))]}"
    METHOD="${QUALITY_METHODS[$(((REMAINDER % 6) / 3))]}"
    SEED="${QUALITY_SEEDS[$((REMAINDER % 3))]}"
    DATASET="${DATASETS[$DATASET_INDEX]}"
    EXTRA+=("--quality-boundary=$BOUNDARY")
    EXTRA+=("--method=$METHOD" "--run-seed=$SEED")
    ;;
  transform|landmark_reconstruction)
    DATASET="${DATASETS[$((TASK_ID / 2))]}"
    METHOD="${METHODS[$((TASK_ID % 2))]}"
    EXTRA+=("--method=$METHOD")
    ;;
  scaling)
    if [[ -n "${SCALING_THREADS:-}" ]]; then
      DATASET="${SCALING_DATASETS[$TASK_ID]}"
      THREAD_COUNT="$SCALING_THREADS"
    else
      DATASET="${SCALING_DATASETS[$((TASK_ID / 5))]}"
      THREAD_COUNT="${THREADS[$((TASK_ID % 5))]}"
    fi
    ;;
  pca)
    if [[ "$BACKEND" == "cpu" && -n "${PCA_THREADS_OVERRIDE:-}" ]]; then
      DATASET_INDEX=$((TASK_ID / 2))
      THREAD_COUNT="$PCA_THREADS_OVERRIDE"
      RANK="${PCA_RANKS[$((TASK_ID % 2))]}"
    elif [[ "$BACKEND" == "cpu" ]]; then
      DATASET_INDEX=$((TASK_ID / 6))
      REMAINDER=$((TASK_ID % 6))
      THREAD_COUNT="${PCA_THREADS[$((REMAINDER / 2))]}"
      RANK="${PCA_RANKS[$((REMAINDER % 2))]}"
    else
      DATASET_INDEX=$((TASK_ID / 2))
      THREAD_COUNT=4
      RANK="${PCA_RANKS[$((TASK_ID % 2))]}"
    fi
    DATASET="${DATASETS[$DATASET_INDEX]}"
    EXTRA+=("--rank=$RANK")
    ;;
  pca_accuracy)
    DATASET_INDEX=$((TASK_ID / 2))
    RANK="${PCA_RANKS[$((TASK_ID % 2))]}"
    DATASET="${DATASETS[$DATASET_INDEX]}"
    THREAD_COUNT=4
    EXTRA+=("--rank=$RANK")
    ;;
  aggregate)
    THREAD_COUNT=1
    ;;
  *)
    echo "unknown mode: $MODE" >&2
    exit 2
    ;;
esac

ALLOCATED_CPUS="${SLURM_CPUS_PER_TASK:-${SLURM_CPUS_ON_NODE:-}}"
if [[ "$ALLOCATED_CPUS" =~ ^[0-9]+$ ]] && \
   (( THREAD_COUNT > ALLOCATED_CPUS )); then
  echo "Requested $THREAD_COUNT threads but Slurm allocated only " \
    "$ALLOCATED_CPUS CPUs per task." >&2
  exit 2
fi

export OMP_NUM_THREADS="$THREAD_COUNT"
export OPENBLAS_NUM_THREADS="$THREAD_COUNT"
export MKL_NUM_THREADS="$THREAD_COUNT"
export RCPP_PARALLEL_NUM_THREADS="$THREAD_COUNT"

MEASURE_DIR="$OUTPUT_ROOT/measurement/$MODE/$DATASET/$BACKEND"
PREFIX="$MEASURE_DIR/${SLURM_JOB_ID:-local}_${TASK_ID}"
mkdir -p "$MEASURE_DIR" "$BASE_DIR/benchmark_logs"
SCHEDULER_DIR="$OUTPUT_ROOT/scheduler_status/$MODE/$DATASET/$BACKEND"
SCHEDULER_STATUS="$SCHEDULER_DIR/${SLURM_JOB_ID:-local}_${TASK_ID}.csv"
mkdir -p "$SCHEDULER_DIR"

record_scheduler_status() {
  local status="$1"
  local code="$2"
  printf 'mode,dataset,backend,job_id,array_task_id,status,exit_code\n' \
    > "$SCHEDULER_STATUS"
  printf '%s,%s,%s,%s,%s,%s,%s\n' \
    "$MODE" "$DATASET" "$BACKEND" "${SLURM_JOB_ID:-local}" \
    "$TASK_ID" "$status" "$code" >> "$SCHEDULER_STATUS"
}
trap 'record_scheduler_status terminated 143; exit 143' TERM
trap 'record_scheduler_status interrupted 130; exit 130' INT

NV=()
if [[ "$BACKEND" == "cuda" ]]; then NV=(--nv); fi

COMMAND=(
  "$CONTAINER" exec "${NV[@]}" --cleanenv
  --bind "$BASE_DIR:$BASE_DIR"
  --pwd "$BASE_DIR"
  "${FASTEMBEDR_CONTAINER_R_ENV[@]}"
  --env "FASTEMBEDR_IMAGE_SHA256=$IMAGE_SHA256"
  --env "OMP_NUM_THREADS=$THREAD_COUNT"
  --env "OPENBLAS_NUM_THREADS=$THREAD_COUNT"
  --env "MKL_NUM_THREADS=$THREAD_COUNT"
  --env "RCPP_PARALLEL_NUM_THREADS=$THREAD_COUNT"
  "$IMAGE" "$FASTEMBEDR_RSCRIPT"
  "$SUITE/common/run_validation.R"
  "--mode=$MODE"
  "--base-dir=$BASE_DIR"
  "--data-root=$DATA_ROOT"
  "--input-root=$INPUT_ROOT"
  "--output-root=$OUTPUT_ROOT"
  "--image=$IMAGE"
  "--dataset=$DATASET"
  "--backend=$BACKEND"
  "--threads=$THREAD_COUNT"
  "--perplexity=${PERPLEXITY:-30}"
  "--timing-reps=${TIMING_REPS:-5}"
  "--seeds=${SEEDS:-4,17,29}"
  "--max-n=${MAX_N:-70000}"
  "--quality-n=${QUALITY_N:-2000}"
  "--longrun-n=${LONGRUN_N:-2000}"
  "--landmark-fraction=${LANDMARK_FRACTION:-0.2}"
  "--expected-version=$EXPECTED_VERSION"
  "${EXTRA[@]}"
)

echo "[$(date --iso-8601=seconds)] mode=$MODE backend=$BACKEND " \
  "dataset=$DATASET threads=$THREAD_COUNT allocated_cpus=${ALLOCATED_CPUS:-unknown} " \
  "task=$TASK_ID"
set +e
bash "$SUITE/common/run_measured.sh" "$BACKEND" "$PREFIX" -- "${COMMAND[@]}"
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  record_scheduler_status completed 0
else
  record_scheduler_status failed "$STATUS"
fi
exit "$STATUS"
