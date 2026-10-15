#!/usr/bin/env bash
set -euo pipefail

free_gb=${DEEP1B_SCRATCH_FREE_GB:-}
[[ "$free_gb" =~ ^[0-9]+$ && "$free_gb" -ge 600 ]] || {
    echo "Set DEEP1B_SCRATCH_FREE_GB from a current myquota reading" \
        "(at least 600 GB free)." >&2
    exit 1
}
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
expected=${FASTEMBEDR_IMAGE_SHA256:?Set FASTEMBEDR_IMAGE_SHA256}
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
export DEEP1B_ONLY_BACKEND=cpu
export DEEP1B_CASE_FILTER=cpu_umap_1b
export DEEP1B_ALLOW_BILLION=1
export DEEP1B_PRUNE_BILLION=1
export DEEP1B_SERIALIZE=1
bash "$suite/submit.sh" billion deep
