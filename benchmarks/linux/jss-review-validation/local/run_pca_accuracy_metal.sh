#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/Users/stefano/HPC-firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
DATA_ROOT="${DATA_ROOT:-/Users/stefano/Documents/fastEmbedR/Data}"
INPUT_ROOT="${INPUT_ROOT:-$BASE_DIR/fastEmbedR-input/jss_validation}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
R_SCRIPT="${R_SCRIPT:-Rscript}"
THREADS="${THREADS:-4}"

DEFAULT_DATASETS=(
  COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST
  imagenet MetRef mass41 TabulaMuris Macosko2015_retina
)
if [[ -n "${DATASETS_CSV:-}" ]]; then
  IFS=',' read -r -a DATASETS <<< "$DATASETS_CSV"
else
  DATASETS=("${DEFAULT_DATASETS[@]}")
fi

for dataset in "${DATASETS[@]}"; do
  for rank in 2 50; do
    echo "dataset=$dataset rank=$rank backend=metal"
    "$R_SCRIPT" "$SUITE/common/run_validation.R" \
      --mode=pca_accuracy \
      --base-dir="$BASE_DIR" \
      --data-root="$DATA_ROOT" \
      --input-root="$INPUT_ROOT" \
      --output-root="$OUTPUT_ROOT" \
      --dataset="$dataset" \
      --backend=metal \
      --threads="$THREADS" \
      --rank="$rank" \
      --expected-version="$EXPECTED_VERSION"
  done
done
