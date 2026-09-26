#!/usr/bin/env bash

set -euo pipefail

MODE="${1:?mode is required}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
DATA_ROOT="${DATA_ROOT:-$BASE_DIR/Data}"
INPUT_ROOT="${INPUT_ROOT:?INPUT_ROOT is required}"
OUTPUT_ROOT="${OUTPUT_ROOT:?OUTPUT_ROOT is required}"
TASK_ID="${SLURM_ARRAY_TASK_ID:-0}"
THREADS="${SLURM_CPUS_PER_TASK:-4}"
CONTAINER="$(command -v apptainer || command -v singularity || true)"

source "$SUITE/common/container_runtime.sh"
source "$SUITE/common/campaign_submit.sh"
campaign_verify_suite_revision

DATASETS=(
  COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST
  imagenet MetRef mass41 TabulaMuris Macosko2015_retina
)
R_METHODS=(
  fastembedr_pca irlba_pca fastembedr_tsne rtsne fitsne
  fastembedr_umap uwot uwot_fast_sgd r_umap
)
R_CUDA_METHODS=(fastembedr_pca fastembedr_tsne fastembedr_umap)
PRCOMP_DATASETS=(COIL20 USPS MetRef)
PYTHON_CPU_METHODS=(
  sklearn_pca sklearn_tsne python_opentsne python_umap
)
PYTHON_CUDA_METHODS=(cuml_pca cuml_tsne cuml_umap)

[[ -n "$CONTAINER" ]] || { echo "container runtime not found" >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "missing image: $IMAGE" >&2; exit 1; }

BACKEND=cpu
case "$MODE" in
  inputs)
    DATASET="${DATASETS[$TASK_ID]}"
    COMMAND=(
      "$CONTAINER" exec --cleanenv --bind "$BASE_DIR:$BASE_DIR"
      --pwd "$BASE_DIR" "${FASTEMBEDR_CONTAINER_R_ENV[@]}"
      "$IMAGE" "$FASTEMBEDR_RSCRIPT"
      "$SUITE/common/prepare_comparator_inputs.R"
      "--base-dir=$BASE_DIR" "--data-root=$DATA_ROOT"
      "--input-root=$INPUT_ROOT" "--output-root=$OUTPUT_ROOT"
      "--dataset=$DATASET"
    )
    ;;
  r_cpu)
    COUNT="${#R_METHODS[@]}"
    GENERAL_TASKS=$(( ${#DATASETS[@]} * COUNT ))
    if (( TASK_ID < GENERAL_TASKS )); then
      DATASET="${DATASETS[$((TASK_ID / COUNT))]}"
      METHOD="${R_METHODS[$((TASK_ID % COUNT))]}"
    else
      PRCOMP_INDEX=$(( TASK_ID - GENERAL_TASKS ))
      if (( PRCOMP_INDEX >= ${#PRCOMP_DATASETS[@]} )); then
        echo "R comparator task index is out of range: $TASK_ID" >&2
        exit 2
      fi
      DATASET="${PRCOMP_DATASETS[$PRCOMP_INDEX]}"
      METHOD=stats_prcomp
    fi
    COMMAND=(
      "$CONTAINER" exec --cleanenv --bind "$BASE_DIR:$BASE_DIR"
      --pwd "$BASE_DIR" "${FASTEMBEDR_CONTAINER_R_ENV[@]}"
      --env "OMP_NUM_THREADS=$THREADS"
      --env "OPENBLAS_NUM_THREADS=$THREADS"
      "$IMAGE" "$FASTEMBEDR_RSCRIPT"
      "$SUITE/common/run_r_comparator.R"
      "--base-dir=$BASE_DIR" "--data-root=$DATA_ROOT"
      "--input-root=$INPUT_ROOT" "--output-root=$OUTPUT_ROOT"
      "--dataset=$DATASET" "--method=$METHOD" "--threads=$THREADS"
      "--backend=cpu"
    )
    ;;
  r_cuda)
    BACKEND=cuda
    COUNT="${#R_CUDA_METHODS[@]}"
    MAX_TASKS=$(( ${#DATASETS[@]} * COUNT ))
    if (( TASK_ID >= MAX_TASKS )); then
      echo "R CUDA comparator task index is out of range: $TASK_ID" >&2
      exit 2
    fi
    DATASET="${DATASETS[$((TASK_ID / COUNT))]}"
    METHOD="${R_CUDA_METHODS[$((TASK_ID % COUNT))]}"
    COMMAND=(
      "$CONTAINER" exec --nv --cleanenv --bind "$BASE_DIR:$BASE_DIR"
      --pwd "$BASE_DIR" "${FASTEMBEDR_CONTAINER_R_ENV[@]}"
      --env "OMP_NUM_THREADS=$THREADS"
      --env "OPENBLAS_NUM_THREADS=$THREADS"
      "$IMAGE" "$FASTEMBEDR_RSCRIPT"
      "$SUITE/common/run_r_comparator.R"
      "--base-dir=$BASE_DIR" "--data-root=$DATA_ROOT"
      "--input-root=$INPUT_ROOT" "--output-root=$OUTPUT_ROOT"
      "--dataset=$DATASET" "--method=$METHOD" "--threads=$THREADS"
      "--backend=cuda"
    )
    ;;
  python_cpu|python_cuda)
    if [[ "$MODE" == python_cuda ]]; then
      METHODS=("${PYTHON_CUDA_METHODS[@]}")
      BACKEND=cuda
      NV=(--nv)
    else
      METHODS=("${PYTHON_CPU_METHODS[@]}")
      NV=()
    fi
    COUNT="${#METHODS[@]}"
    DATASET="${DATASETS[$((TASK_ID / COUNT))]}"
    METHOD="${METHODS[$((TASK_ID % COUNT))]}"
    OUTPUT_DIR="$OUTPUT_ROOT/workflow_comparators/$MODE/$DATASET/$METHOD"
    COMMAND=(
      "$CONTAINER" exec "${NV[@]}" --cleanenv
      --bind "$BASE_DIR:$BASE_DIR" --pwd "$BASE_DIR"
      "${FASTEMBEDR_CONTAINER_BASE_ENV[@]}"
      --env "OMP_NUM_THREADS=$THREADS"
      --env "OPENBLAS_NUM_THREADS=$THREADS"
      "$IMAGE" "$FASTEMBEDR_PYTHON"
      "$SUITE/common/run_python_comparator.py"
      "--input-dir=$INPUT_ROOT/$DATASET/workflow_comparators"
      "--output-dir=$OUTPUT_DIR" "--dataset=$DATASET"
      "--method=$METHOD" "--backend=$BACKEND" "--threads=$THREADS"
    )
    ;;
  *)
    echo "unknown comparator mode: $MODE" >&2
    exit 2
    ;;
esac

METHOD="${METHOD:-inputs}"
MEASURE_DIR="$OUTPUT_ROOT/measurement/workflow_comparators/$MODE"
MEASURE_DIR+="/$DATASET/$METHOD"
PREFIX="$MEASURE_DIR/${SLURM_JOB_ID:-local}_${TASK_ID}"
mkdir -p "$MEASURE_DIR"
echo "[$(date --iso-8601=seconds)] mode=$MODE dataset=$DATASET method=$METHOD"
bash "$SUITE/common/run_measured.sh" "$BACKEND" "$PREFIX" -- \
  "${COMMAND[@]}"

if [[ "$MODE" != inputs ]]; then
  OUTPUT_DIR="$OUTPUT_ROOT/workflow_comparators/$MODE/$DATASET/$METHOD"
  PLOT=(
    "$CONTAINER" exec --cleanenv --bind "$BASE_DIR:$BASE_DIR"
    --pwd "$BASE_DIR" "${FASTEMBEDR_CONTAINER_R_ENV[@]}"
    "$IMAGE" "$FASTEMBEDR_RSCRIPT"
    "$SUITE/common/plot_method_output.R"
    "--input=$OUTPUT_DIR/embedding.csv"
    "--output=$OUTPUT_DIR/embedding.png"
  )
  "${PLOT[@]}"
fi
