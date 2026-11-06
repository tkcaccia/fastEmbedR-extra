#!/usr/bin/env bash
set -euo pipefail
[[ "${FASTEMBEDR_HPC_GPU_PAUSED:-1}" == 0 ]] || {
    echo 'UCT GPU submissions remain paused, including controllers.' >&2
    exit 2
}

base=${FASTEMBEDR_BASE:-/scratch/firenze/NN}
suite=${FASTEMBEDR_SUITE_ROOT:-$base/benchmark_scripts}
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
export BASE_DIR="$base"
export IMAGE="${FASTEMBEDR_IMAGE:-$base/singularity/fastembedr_cuda.sif}"
export PREFLIGHT_ROOT="$root/jss_preflight"
export JSS_CAMPAIGN_ID="$(basename "$root")_${role}"
export TIMING_REPS=${TIMING_REPS:-5}
if [[ -f "$root/jss_suite.sha256" ]]; then
    sha256sum -c "$root/jss_suite.sha256" >/dev/null || {
        echo 'JSS benchmark revision changed after staging.' >&2
        exit 3
    }
    (cd "$suite/jss-review-validation" &&
        sha256sum -c FILES.sha256 --status) || {
        echo 'JSS suite files changed after staging.' >&2
        exit 3
    }
fi
bash "$suite/jss-review-validation/submit_complete_campaign.sh"
