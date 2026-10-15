#!/usr/bin/env bash

set -euo pipefail
SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:?Provide an output CSV path.}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
R_SCRIPT="${R_SCRIPT:-Rscript}"
"$R_SCRIPT" "$SUITE/common/run_clustering_scale.R" \
  metal "$OUTPUT" "$EXPECTED_VERSION"
