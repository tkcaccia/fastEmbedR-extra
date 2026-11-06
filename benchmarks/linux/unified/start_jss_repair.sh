#!/usr/bin/env bash
# Stage a source-locked JSS repair campaign without touching active jobs.
set -euo pipefail
echo "policy_rejected: archived JSS repair includes file-backed HPC work." >&2
exit 78
[[ "${FASTEMBEDR_HPC_GPU_PAUSED:-1}" == 0 ]] || {
    echo 'UCT GPU submissions remain paused, including controllers.' >&2
    exit 2
}

base=$(realpath "${FASTEMBEDR_BASE:-/scratch/firenze/NN}")
suite=$(realpath "${FASTEMBEDR_SUITE_ROOT:?Isolated suite root required}")
image=$(realpath "${FASTEMBEDR_IMAGE:?Candidate image required}")
expected=${FASTEMBEDR_IMAGE_SHA256:?Image SHA-256 required}
[[ "$suite" != "$base/benchmark_scripts" ]] || {
    echo 'Use an isolated suite while Deep1B jobs are active.' >&2
    exit 2
}
test -s "$suite/unified/stage_jss.sh"
test -s "$suite/jss-review-validation/FILES.sha256"
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
(cd "$suite/jss-review-validation" &&
    sha256sum -c FILES.sha256 --status)

parent=$base/fastEmbedR-results/unified
mkdir -p "$parent"
root=${JSS_REPAIR_ROOT:-}
if [[ -z "$root" ]]; then
    root=$(mktemp -d "$parent/$(date -u +%Y%m%dT%H%M%SZ)_jssrepair_XXXX")
    printf '%s  %s\n' "$expected" "$image" > "$root/image.sha256"
    sha256sum "$suite/jss-review-validation/FILES.sha256" \
        > "$root/jss_suite.sha256"
    sha256sum "$suite/unified/stage_jss.sh" \
        "$suite/unified/launch_jss.sh" \
        > "$root/staging_source.sha256"
else
    root=$(realpath "$root")
    [[ "$root" == "$parent/"* ]] || exit 2
    sha256sum -c "$root/image.sha256" --status
    sha256sum -c "$root/jss_suite.sha256" --status
    sha256sum -c "$root/staging_source.sha256" --status
fi
export FASTEMBEDR_BASE="$base" FASTEMBEDR_SUITE_ROOT="$suite"
export FASTEMBEDR_IMAGE="$image" FASTEMBEDR_IMAGE_SHA256="$expected"
export JSS_ROLES="${JSS_REPAIR_ROLES:-paired extended}"
if [[ " $JSS_ROLES " == *' extended '* && \
      ! -s "$base/Data/BigANN/turing/1000000000/base.1000000000.fbin" ]]; then
    echo 'Turing input is absent; extended file-backed results will be' \
      'incomplete until that input is restored.' >&2
fi
bash "$suite/unified/stage_jss.sh" "$root"
printf 'JSS repair root: %s\n' "$root"
