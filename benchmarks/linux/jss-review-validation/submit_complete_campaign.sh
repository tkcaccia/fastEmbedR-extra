#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
PREFLIGHT_ROOT="${PREFLIGHT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
CAMPAIGN_PARENT="${CAMPAIGN_PARENT:-$BASE_DIR/fastEmbedR-results/jss_validation/campaigns}"
JSS_CAMPAIGN_ID="${JSS_CAMPAIGN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
JSS_CAMPAIGN_DIR="$CAMPAIGN_PARENT/$JSS_CAMPAIGN_ID"
INPUT_ROOT="$JSS_CAMPAIGN_DIR/input"
OUTPUT_ROOT="$JSS_CAMPAIGN_DIR/results"
JSS_LEDGER="$JSS_CAMPAIGN_DIR/jobs.tsv"
CONTROLLER="$SUITE/slurm/run_complete_campaign_controller_cpu1.sh"

cd "$BASE_DIR"
mkdir -p "$JSS_CAMPAIGN_DIR" "$INPUT_ROOT" "$OUTPUT_ROOT" benchmark_logs

EXPECTED_VERSION="$EXPECTED_VERSION" OUTPUT_ROOT="$PREFLIGHT_ROOT" \
  IMAGE="$IMAGE" bash "$SUITE/verify_preflight.sh"

CPU_IDENTITY="$PREFLIGHT_ROOT/identity/cpu/identity.csv"
CUDA_IDENTITY="$PREFLIGHT_ROOT/identity/cuda/identity.csv"
IDENTITY_VALUES="$(python3 - "$CPU_IDENTITY" "$CUDA_IDENTITY" <<'PY'
import csv
import sys

rows = []
for path in sys.argv[1:]:
    with open(path, newline="") as handle:
        rows.append(next(csv.DictReader(handle)))
fields = ("package_version", "dll_sha256", "image_sha256")
for field in fields:
    if rows[0][field] != rows[1][field]:
        raise SystemExit(f"CPU/CUDA identity mismatch for {field}")
print(rows[0]["image_sha256"] + "|" + rows[0]["dll_sha256"])
PY
)"
IFS='|' read -r FASTEMBEDR_IMAGE_SHA256 FASTEMBEDR_DLL_SHA256 \
  <<< "$IDENTITY_VALUES"

export BASE_DIR SUITE IMAGE INPUT_ROOT OUTPUT_ROOT EXPECTED_VERSION
export FASTEMBEDR_IMAGE_SHA256 JSS_CAMPAIGN_ID JSS_CAMPAIGN_DIR JSS_LEDGER
export JSS_RETRY_SECONDS="${JSS_RETRY_SECONDS:-60}"
export JSS_MAX_SUBMIT_ATTEMPTS="${JSS_MAX_SUBMIT_ATTEMPTS:-720}"
export JSS_STAGE=shared_inputs

source "$SUITE/common/campaign_submit.sh"
campaign_require_environment
campaign_init_ledger

cat > "$JSS_CAMPAIGN_DIR/campaign_manifest.txt" <<EOF
campaign_id=$JSS_CAMPAIGN_ID
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
base_dir=$BASE_DIR
suite=$SUITE
image=$IMAGE
image_sha256=$FASTEMBEDR_IMAGE_SHA256
fastembedr_dll_sha256=$FASTEMBEDR_DLL_SHA256
expected_version=$EXPECTED_VERSION
input_root=$INPUT_ROOT
output_root=$OUTPUT_ROOT
preflight_root=$PREFLIGHT_ROOT
retry_seconds=$JSS_RETRY_SECONDS
max_submit_attempts=$JSS_MAX_SUBMIT_ATTEMPTS
EOF

CONTROLLER_JOB="$(campaign_submit_job \
  controller controller_shared_inputs '' "$CONTROLLER" '' shared_inputs)"

cat <<EOF
Started staged fastEmbedR JSS campaign.
  campaign:   $JSS_CAMPAIGN_ID
  controller: $CONTROLLER_JOB
  ledger:     $JSS_LEDGER
  results:    $OUTPUT_ROOT

Monitor with:
  squeue -u \"$USER\"
  tail -f $BASE_DIR/benchmark_logs/feR_JSS_ctl_${CONTROLLER_JOB}.out
EOF
