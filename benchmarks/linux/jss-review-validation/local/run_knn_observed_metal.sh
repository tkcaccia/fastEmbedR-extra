#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/Users/stefano/Documents/fastEmbedR}"
SUITE="${SUITE:-/Users/stefano/Documents/umap/output/fastembedr_jss_review_validation}"
DATA_ROOT="${DATA_ROOT:-$BASE_DIR/Data}"
INPUT_ROOT="${INPUT_ROOT:-$BASE_DIR/fastEmbedR-input/jss_validation}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
DATASETS_CSV="${DATASETS_CSV:-COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41,TabulaMuris,Macosko2015_retina}"

IFS=',' read -r -a DATASETS <<< "$DATASETS_CSV"
for DATASET in "${DATASETS[@]}"; do
  Rscript "$SUITE/common/run_validation.R" \
    --mode=knn_observed \
    --base-dir="$BASE_DIR" \
    --data-root="$DATA_ROOT" \
    --input-root="$INPUT_ROOT" \
    --output-root="$OUTPUT_ROOT" \
    --dataset="$DATASET" \
    --backend=metal \
    --threads=4 \
    --perplexity=30 \
    --max-n=2147483647 \
    --expected-version="$EXPECTED_VERSION"
done
