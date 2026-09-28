#!/usr/bin/env bash
set -euo pipefail

SUITE="${SUITE:-/scratch/firenze/NN/benchmark_scripts/fastembedr_jss_review_validation}"
export SUITE
export FULL_CUDA_PAIR=TRUE
export TIMING_REPS="${TIMING_REPS:-3}"
export METHOD_TIMEOUT_SECONDS="${METHOD_TIMEOUT_SECONDS:-151200}"
exec bash "$SUITE/submit_complete_campaign.sh"
