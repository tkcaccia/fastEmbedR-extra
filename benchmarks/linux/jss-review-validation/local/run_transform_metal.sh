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
  input="$INPUT_ROOT/$dataset/matched_inputs.rds"
  if [[ ! -f "$input" ]]; then
    echo "Missing matched input: $input" >&2
    echo "Copy the shared HPC input locally before running Metal." >&2
    exit 1
  fi
  for method in tsne umap; do
    echo "dataset=$dataset method=$method backend=metal"
    "$R_SCRIPT" "$SUITE/common/run_validation.R" \
      --mode=transform \
      --base-dir="$BASE_DIR" \
      --data-root="$DATA_ROOT" \
      --input-root="$INPUT_ROOT" \
      --output-root="$OUTPUT_ROOT" \
      --dataset="$dataset" \
      --backend=metal \
      --threads="$THREADS" \
      --method="$method" \
      --expected-version="$EXPECTED_VERSION"
  done
done
