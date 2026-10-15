#!/usr/bin/env bash
# Source-lock and submit JSS and Deep1B as independent HPC campaigns.
set -euo pipefail

[[ -n "${SLURM_JOB_ID:-}" ]] || {
    echo 'Use submit_from_login.sh; do not run containers on login.' >&2
    exit 2
}
base=${FASTEMBEDR_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts
image=${FASTEMBEDR_IMAGE:-$base/singularity/fastembedr_cuda.sif}
test -s "$image"
test -s "$suite/jss-review-validation/submit_complete_campaign.sh"
test -s "$suite/massive-data/deep1b/submit_matrix.sh"
test -d "$base/Data/BigANN/deep/1000000000"
[[ "${DEEP1B_QUOTA_FREE_BYTES:-}" =~ ^[0-9]+$ ]] || {
    echo 'Missing numeric DEEP1B_QUOTA_FREE_BYTES.' >&2
    exit 2
}
digest=$(sha256sum "$image" | awk '{print $1}')
if [[ -n "${FASTEMBEDR_IMAGE_SHA256:-}" &&
      "$FASTEMBEDR_IMAGE_SHA256" != "$digest" ]]; then
    echo 'Image SHA-256 differs from the expected release.' >&2
    exit 3
fi
identity_file=$suite/jss-review-validation/common/image_source_identity.csv
python3 - "$identity_file" "$digest" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="") as stream:
    matches = [row for row in csv.DictReader(stream)
               if row["image_sha256"] == sys.argv[2]]
if len(matches) != 1:
    raise SystemExit("JSS lacks one reviewed identity for this image")
PY
parent=$base/fastEmbedR-results/unified
mkdir -p "$parent"
root=$(mktemp -d "$parent/$(date -u +%Y%m%dT%H%M%SZ)_XXXXXX")
printf '%s  %s\n' "$digest" "$image" > "$root/image.sha256"
sha256sum "$suite/unified/launch.sh" \
    "$suite/unified/submit.sbatch" \
    "$suite/unified/submit_from_login.sh" \
    "$suite/jss-review-validation/submit_complete_campaign.sh" \
    "$suite/massive-data/deep1b/submit_matrix.sh" \
    > "$root/source.sha256"
export FASTEMBEDR_IMAGE_SHA256="$digest"
export DEEP1B_IMAGE_SHA256="$digest"
export DEEP1B_IMAGE="$image" DEEP1B_BASE="$base"
export BASE_DIR="$base" IMAGE="$image"
export TIMING_REPS=${TIMING_REPS:-5}

set +e
FULL_CUDA_PAIR=TRUE INCLUDE_NOMAD=TRUE \
JSS_CAMPAIGN_ID="$(date -u +%Y%m%dT%H%M%SZ)_${SLURM_JOB_ID}_paired" \
PREFLIGHT_ROOT="$root/jss_paired_preflight" \
bash "$suite/jss-review-validation/submit_complete_campaign.sh" \
    > "$root/jss_paired_launch.log" 2>&1 &
jss_paired_pid=$!
FULL_CUDA_PAIR=FALSE INCLUDE_NOMAD=FALSE \
JSS_CAMPAIGN_ID="$(date -u +%Y%m%dT%H%M%SZ)_${SLURM_JOB_ID}_extended" \
PREFLIGHT_ROOT="$root/jss_extended_preflight" \
bash "$suite/jss-review-validation/submit_complete_campaign.sh" \
    > "$root/jss_extended_launch.log" 2>&1 &
jss_extended_pid=$!
bash "$suite/massive-data/deep1b/submit_matrix.sh" \
    > "$root/deep1b_launch.log" 2>&1 &
deep_pid=$!
wait "$jss_paired_pid"
jss_paired_status=$?
wait "$jss_extended_pid"
jss_extended_status=$?
wait "$deep_pid"
deep_status=$?
set -e
printf 'campaign\tlaunch_exit_code\tlog\n' > "$root/launch_status.tsv"
printf 'jss_paired_nomad\t%s\tjss_paired_launch.log\n' \
    "$jss_paired_status" \
    >> "$root/launch_status.tsv"
printf 'jss_extended\t%s\tjss_extended_launch.log\n' \
    "$jss_extended_status" \
    >> "$root/launch_status.tsv"
printf 'deep1b\t%s\tdeep1b_launch.log\n' "$deep_status" \
    >> "$root/launch_status.tsv"
printf 'Unified launch record: %s\n' "$root"
cat "$root/launch_status.tsv"
if ((jss_paired_status != 0 || jss_extended_status != 0 ||
      deep_status != 0)); then
    echo 'Inspect both launch logs; submitted jobs were not canceled.' >&2
    exit 1
fi
