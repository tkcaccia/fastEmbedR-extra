#!/usr/bin/env bash
set -euo pipefail

SUITE="${SUITE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export SUITE
export FULL_CUDA_PAIR=TRUE
export TIMING_REPS="${TIMING_REPS:-3}"
exec bash "$SUITE/submit_complete_campaign.sh"
