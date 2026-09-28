#!/usr/bin/env bash
set -euo pipefail

SUITE="${SUITE:-/scratch/firenze/NN/benchmark_scripts/fastembedr_jss_review_validation}"
JSS_CAMPAIGN_DIR="${JSS_CAMPAIGN_DIR:?campaign directory required}"
INPUT_ROOT="${INPUT_ROOT:?input root required}"
OUTPUT_ROOT="${OUTPUT_ROOT:?output root required}"
source "$SUITE/common/campaign_submit.sh"
campaign_verify_suite_revision
python3 "$SUITE/common/audit_full_cuda_pair.py" \
  "$JSS_CAMPAIGN_DIR" "$INPUT_ROOT" "$OUTPUT_ROOT"
