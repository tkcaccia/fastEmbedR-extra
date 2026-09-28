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

bash "$SUITE/common/validate_slurm_resources.sh" "$SUITE"
Rscript "$SUITE/common/validate_benchmark_logic.R"

(
  cd "$SUITE"
  sha256sum -c FILES.sha256
)
bash "$SUITE/common/validate_campaign_schedule.sh"
FASTEMBEDR_SUITE_MANIFEST_SHA256="$(
  sha256sum "$SUITE/FILES.sha256" | awk '{print $1}')"
cp "$SUITE/FILES.sha256" "$JSS_CAMPAIGN_DIR/source_FILES.sha256"

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
export FASTEMBEDR_SUITE_MANIFEST_SHA256
export JSS_RETRY_SECONDS="${JSS_RETRY_SECONDS:-60}"
export JSS_MAX_SUBMIT_ATTEMPTS="${JSS_MAX_SUBMIT_ATTEMPTS:-720}"
export METHOD_TIMEOUT_SECONDS="${METHOD_TIMEOUT_SECONDS:-7200}"
export FULL_CUDA_PAIR="${FULL_CUDA_PAIR:-FALSE}"
export TIMING_REPS="${TIMING_REPS:-5}"
export INCLUDE_NOMAD="${INCLUDE_NOMAD:-FALSE}"
NOMAD_IDENTITY=not_requested
if [[ "$INCLUDE_NOMAD" == TRUE ]]; then
  [[ "$FULL_CUDA_PAIR" == TRUE ]] || {
    echo "NOMAD is supported only in the full CUDA campaign." >&2
    exit 2
  }
  source "$SUITE/common/container_runtime.sh"
  CONTAINER="$(command -v apptainer || command -v singularity || true)"
  [[ -n "$CONTAINER" ]] || {
    echo "A container runtime is required for NOMAD." >&2
    exit 1
  }
  NOMAD_IDENTITY="$("$CONTAINER" exec --cleanenv \
    "${FASTEMBEDR_CONTAINER_BASE_ENV[@]}" "$IMAGE" \
    "$FASTEMBEDR_NOMAD_PYTHON" -c '
import importlib.metadata as metadata
import hashlib
import json
from pathlib import Path
import re
import subprocess
import torch
from urllib.parse import unquote, urlparse
from nomad_projection import NomadProjection
import nomad_projection
distribution = metadata.distribution("nomad-projection")
direct = json.loads(distribution.read_text("direct_url.json") or "{}")
commit = direct.get("vcs_info", {}).get("commit_id", "")
if not commit:
    url = urlparse(direct.get("url", ""))
    if url.scheme != "file" or not url.path:
        raise SystemExit("NOMAD needs a pinned Git or local checkout")
    source = Path(unquote(url.path)).resolve()
    commit = subprocess.check_output([
        "git", "-c", f"safe.directory={source}",
        "-C", str(source), "rev-parse", "HEAD"
    ], text=True).strip()
    installed = Path(nomad_projection.__file__).parent
    original = source / "nomad_projection"
    files = sorted(path.relative_to(installed)
                   for path in installed.rglob("*.py"))
    source_files = sorted(path.relative_to(original)
                          for path in original.rglob("*.py"))
    if not files or files != source_files:
        raise SystemExit("NOMAD source module set differs")
    for relative in files:
        installed_hash = hashlib.sha256(
            (installed / relative).read_bytes()).digest()
        source_hash = hashlib.sha256(
            (original / relative).read_bytes()).digest()
        if installed_hash != source_hash:
            raise SystemExit(f"Installed NOMAD differs at {relative}")
if not re.fullmatch(r"[0-9a-f]{40}", commit):
    raise SystemExit("Install NOMAD from a pinned Git commit in the image")
if not torch.version.cuda:
    raise SystemExit("The image lacks CUDA-enabled PyTorch")
print(distribution.version + "|" + commit)
')" || {
    echo "NOMAD is unavailable or not source-pinned in this image." >&2
    exit 1
  }
fi
if [[ "$FULL_CUDA_PAIR" == TRUE ]]; then
  export JSS_STAGE=full_precompute
else
  command -v flock >/dev/null || {
    echo "The staged CPU/CUDA controller requires flock." >&2
    exit 1
  }
  export JSS_STAGE=comparator_preflight
fi

source "$SUITE/common/campaign_submit.sh"
campaign_require_environment
campaign_init_ledger
campaign_record_stage launcher verified \
  "version=$EXPECTED_VERSION image=$FASTEMBEDR_IMAGE_SHA256"

cat > "$JSS_CAMPAIGN_DIR/campaign_manifest.txt" <<EOF
campaign_id=$JSS_CAMPAIGN_ID
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
base_dir=$BASE_DIR
suite=$SUITE
image=$IMAGE
image_sha256=$FASTEMBEDR_IMAGE_SHA256
fastembedr_dll_sha256=$FASTEMBEDR_DLL_SHA256
expected_version=$EXPECTED_VERSION
verified_package_version=$EXPECTED_VERSION
suite_manifest_sha256=$FASTEMBEDR_SUITE_MANIFEST_SHA256
suite_manifest=$JSS_CAMPAIGN_DIR/source_FILES.sha256
input_root=$INPUT_ROOT
output_root=$OUTPUT_ROOT
preflight_root=$PREFLIGHT_ROOT
retry_seconds=$JSS_RETRY_SECONDS
max_submit_attempts=$JSS_MAX_SUBMIT_ATTEMPTS
method_timeout_seconds=$METHOD_TIMEOUT_SECONDS
full_cuda_pair=$FULL_CUDA_PAIR
timing_reps=$TIMING_REPS
include_nomad=$INCLUDE_NOMAD
nomad_version_commit=$NOMAD_IDENTITY
EOF

CONTROLLER_JOB="$(campaign_submit_job \
  controller "controller_$JSS_STAGE" '' "$CONTROLLER" '' \
  "$JSS_STAGE")"
campaign_record_stage launcher submitted "controller=$CONTROLLER_JOB"

cat <<EOF
Started staged fastEmbedR JSS campaign.
  package:    fastEmbedR $EXPECTED_VERSION
  image SHA:  $FASTEMBEDR_IMAGE_SHA256
  DLL SHA:    $FASTEMBEDR_DLL_SHA256
  suite SHA:  $FASTEMBEDR_SUITE_MANIFEST_SHA256
  campaign:   $JSS_CAMPAIGN_ID
  controller: $CONTROLLER_JOB
  ledger:     $JSS_LEDGER
  stages:     $JSS_CAMPAIGN_DIR/stages.tsv
  failures:   $JSS_CAMPAIGN_DIR/failures.tsv
  results:    $OUTPUT_ROOT

Monitor with:
  squeue -u \"$USER\"
  tail -f $BASE_DIR/benchmark_logs/feR_JSS_ctl_${CONTROLLER_JOB}.out
EOF
