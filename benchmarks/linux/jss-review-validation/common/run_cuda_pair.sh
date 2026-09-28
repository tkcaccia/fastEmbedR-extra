#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
INPUT_ROOT="${INPUT_ROOT:?INPUT_ROOT is required}"
OUTPUT_ROOT="${OUTPUT_ROOT:?OUTPUT_ROOT is required}"
export N_COMPONENTS=2
source "$SUITE/common/container_runtime.sh"

# Small datasets first; each task publishes its plots before the next wave.
PRIORITY=(7 1 0 5 2 8 9 10 4 3 6)
DATASETS=(
  COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST
  imagenet MetRef mass41 TabulaMuris Macosko2015_retina
)
ARRAY_ID="${SLURM_ARRAY_TASK_ID:?array task ID required}"
[[ "$ARRAY_ID" =~ ^([0-9]|10)$ ]] || exit 2
DATASET_INDEX="${PRIORITY[$ARRAY_ID]}"
DATASET="${DATASETS[$DATASET_INDEX]}"
CONTAINER="$(command -v apptainer || command -v singularity)"
FAILED=0

run_method() {
  local mode="$1" offset="$2" task_id
  task_id="$((DATASET_INDEX * 3 + offset))"
  echo "[$(date --iso-8601=seconds)] $DATASET $mode task=$task_id"
  if ! COMPARATOR_TASK_ID="$task_id" \
      bash "$SUITE/common/run_comparator_task.sh" "$mode"; then
    FAILED=1
  fi
}

publish_pair() {
  local family="$1"
  if ! "$CONTAINER" exec --cleanenv --bind "$BASE_DIR:$BASE_DIR" \
      --pwd "$BASE_DIR" "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
      "$IMAGE" "$FASTEMBEDR_RSCRIPT" \
      "$SUITE/common/plot_cuda_pair.R" \
      "--dataset=$DATASET" "--family=$family" \
      "--input-root=$INPUT_ROOT" "--output-root=$OUTPUT_ROOT"; then
    FAILED=1
  fi
}

run_method r_cuda 1
run_method python_cuda 1
publish_pair tsne
run_method r_cuda 2
run_method python_cuda 2
publish_pair umap
exit "$FAILED"
