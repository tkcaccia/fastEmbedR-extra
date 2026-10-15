#!/usr/bin/env bash

set -euo pipefail
BASE_DIR="${BASE_DIR:-/Users/stefano/HPC-firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
INPUT_ROOT="${INPUT_ROOT:-$BASE_DIR/fastEmbedR-input/jss_validation}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
R_SCRIPT="${R_SCRIPT:-Rscript}"
DATASETS=(COIL20 MetRef MNIST flow18)
for dataset in "${DATASETS[@]}"; do
  input="$INPUT_ROOT/$dataset/clustering_inputs.rds"
  reference="$OUTPUT_ROOT/clustering/$dataset/cpu/memberships.rds"
  [[ -f "$input" && -f "$reference" ]] || {
    echo "Missing paired graph or CPU memberships for $dataset." >&2
    exit 1
  }
  "$R_SCRIPT" "$SUITE/common/run_validation.R" \
    --mode=clustering --base-dir="$BASE_DIR" \
    --input-root="$INPUT_ROOT" --output-root="$OUTPUT_ROOT" \
    --dataset="$dataset" --backend=metal \
    --expected-version="$EXPECTED_VERSION"
done
