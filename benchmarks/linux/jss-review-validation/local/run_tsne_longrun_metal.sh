#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/Users/stefano/HPC-firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
DATA_ROOT="${DATA_ROOT:-$BASE_DIR/Data}"
INPUT_ROOT="${INPUT_ROOT:-$BASE_DIR/fastEmbedR-input/jss_validation}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
R_SCRIPT="${R_SCRIPT:-Rscript}"
THREADS="${THREADS:-4}"

DATASETS=(USPS FashionMNIST MNIST MetRef)
GRIDS=(128 256 512)
ITERATIONS=(50 100 250 500 750 1000)
SEEDS=(4 17 42)

run_one() {
  local dataset="$1"
  local grid="$2"
  local iterations="$3"
  local seed="$4"
  "$R_SCRIPT" "$SUITE/common/run_validation.R" \
    --mode=longrun \
    --base-dir="$BASE_DIR" \
    --data-root="$DATA_ROOT" \
    --input-root="$INPUT_ROOT" \
    --output-root="$OUTPUT_ROOT" \
    --dataset="$dataset" \
    --backend=metal \
    --threads="$THREADS" \
    --perplexity=30 \
    --grid-size="$grid" \
    --normal-iterations="$iterations" \
    --run-seed="$seed" \
    --expected-version="$EXPECTED_VERSION"
}

for dataset in "${DATASETS[@]}"; do
  input="$INPUT_ROOT/$dataset/tsne_longrun_inputs.rds"
  if [[ ! -f "$input" ]]; then
    echo "Missing matched input: $input" >&2
    echo "Copy the HPC long-run inputs locally before running Metal." >&2
    exit 1
  fi
  for grid in "${GRIDS[@]}"; do
    for iterations in "${ITERATIONS[@]}"; do
      run_one "$dataset" "$grid" "$iterations" 42
    done
  done
  run_one "$dataset" 256 750 4
  run_one "$dataset" 256 750 17
done
