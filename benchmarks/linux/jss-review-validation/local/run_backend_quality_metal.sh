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
METHODS=(tsne umap)
BOUNDARIES=(matched_knn full_workflow)
SEEDS=(4 17 42)

for dataset in "${DATASETS[@]}"; do
  input="$INPUT_ROOT/$dataset/matched_inputs.rds"
  if [[ ! -f "$input" ]]; then
    echo "Missing matched input: $input" >&2
    echo "Copy the HPC shared inputs locally; no recomputation is allowed." >&2
    exit 1
  fi
  for boundary in "${BOUNDARIES[@]}"; do
    for method in "${METHODS[@]}"; do
      for seed in "${SEEDS[@]}"; do
        echo "dataset=$dataset method=$method boundary=$boundary seed=$seed"
        "$R_SCRIPT" "$SUITE/common/run_validation.R" \
          --mode=backend_quality \
          --base-dir="$BASE_DIR" \
          --data-root="$DATA_ROOT" \
          --input-root="$INPUT_ROOT" \
          --output-root="$OUTPUT_ROOT" \
          --dataset="$dataset" \
          --backend=metal \
          --threads="$THREADS" \
          --method="$method" \
          --quality-boundary="$boundary" \
          --run-seed="$seed" \
          --expected-version="$EXPECTED_VERSION"
      done
    done
  done
done
