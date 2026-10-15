#!/usr/bin/env bash
set -euo pipefail

base=${FASTEMBEDR_BASE:-/scratch/firenze/NN}
root=${1:?Unified campaign root is required}
role=${2:?JSS role is required}
case "$role" in
    paired)
        export FULL_CUDA_PAIR=TRUE INCLUDE_NOMAD=TRUE
        ;;
    extended)
        export FULL_CUDA_PAIR=FALSE INCLUDE_NOMAD=FALSE
        ;;
    *) echo "Unknown JSS role: $role" >&2; exit 2 ;;
esac
export BASE_DIR="$base" IMAGE="$base/singularity/fastembedr_cuda.sif"
export PREFLIGHT_ROOT="$root/jss_preflight"
export JSS_CAMPAIGN_ID="$(basename "$root")_${role}"
export TIMING_REPS=${TIMING_REPS:-5}
bash "$base/benchmark_scripts/jss-review-validation/submit_complete_campaign.sh"
