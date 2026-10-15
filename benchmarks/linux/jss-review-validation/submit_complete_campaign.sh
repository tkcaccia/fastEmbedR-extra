#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
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
LAUNCH_PHASE=resource_contract
record_launch_status() {
  local code=$? status=FAILED
  (( code == 0 )) && status=SUBMITTED
  printf 'status=%s\nphase=%s\nexit_code=%s\n' \
    "$status" "$LAUNCH_PHASE" "$code" \
    > "$JSS_CAMPAIGN_DIR/launch_status.txt"
}
trap record_launch_status EXIT

[[ -f "$SUITE/common/campaign_submit.sh" ]] || {
  echo "Missing campaign submission helpers in $SUITE" >&2
  exit 1
}
source "$SUITE/common/campaign_submit.sh"
campaign_require_method_timeout || exit $?
bash "$SUITE/common/validate_slurm_resources.sh" "$SUITE"
LAUNCH_PHASE=benchmark_logic
python3 "$SUITE/file_backed/validate_cases.py"
source "$SUITE/common/container_runtime.sh"
CONTAINER="$(command -v apptainer || command -v singularity || true)"
[[ -n "$CONTAINER" && -f "$IMAGE" ]] || {
  echo "Benchmark logic needs the configured container image." >&2
  exit 1
}
"$CONTAINER" exec --cleanenv --bind "$BASE_DIR:$BASE_DIR" \
  --pwd "$BASE_DIR" "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
  "$IMAGE" "$FASTEMBEDR_RSCRIPT" \
  "$SUITE/common/validate_benchmark_logic.R"
LAUNCH_PHASE=comparator_outcomes
python3 "$SUITE/common/validate_comparator_outcomes.py"

LAUNCH_PHASE=source_checksums
(
  cd "$SUITE"
  sha256sum -c FILES.sha256
)
LAUNCH_PHASE=schedule_validation
bash "$SUITE/common/validate_campaign_schedule.sh"
FASTEMBEDR_SUITE_MANIFEST_SHA256="$(
  sha256sum "$SUITE/FILES.sha256" | awk '{print $1}')"
cp "$SUITE/FILES.sha256" "$JSS_CAMPAIGN_DIR/source_FILES.sha256"
LAUNCH_PHASE=source_snapshot
mapfile -t SOURCE_FILES < <(awk '{print $2}' "$SUITE/FILES.sha256")
tar -C "$SUITE" -czf "$JSS_CAMPAIGN_DIR/benchmark_source.tar.gz" \
  FILES.sha256 "${SOURCE_FILES[@]}"
BENCHMARK_SOURCE_ARCHIVE_SHA256="$(
  sha256sum "$JSS_CAMPAIGN_DIR/benchmark_source.tar.gz" | awk '{print $1}'
)"

LAUNCH_PHASE=preflight_evidence
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

LAUNCH_PHASE=package_source_identity
SOURCE_TARBALL="/opt/fastembedr-source/fastEmbedR_0.1.tar.gz"
SOURCE_SHA256="$("$CONTAINER" exec --cleanenv "$IMAGE" \
  sha256sum "$SOURCE_TARBALL" | awk '{print $1}')"
SOURCE_IDENTITY="$(IMAGE_SHA="$FASTEMBEDR_IMAGE_SHA256" \
  SOURCE_SHA="$SOURCE_SHA256" \
  python3 - "$SUITE/common/image_source_identity.csv" <<'PY'
import csv
import os
import sys

with open(sys.argv[1], newline="") as handle:
    rows = [row for row in csv.DictReader(handle)
            if row["image_sha256"] == os.environ["IMAGE_SHA"]]
if len(rows) != 1:
    raise SystemExit("Image has no unique reviewed source identity")
row = rows[0]
if row["source_archive_sha256"] != os.environ["SOURCE_SHA"]:
    raise SystemExit("Embedded package source checksum does not match")
print(row["package_source_commit"] + "|" +
      row["local_patch_sha256"])
PY
)"
IFS='|' read -r PACKAGE_SOURCE_COMMIT LOCAL_PATCH_SHA256 \
  <<< "$SOURCE_IDENTITY"

export BASE_DIR SUITE IMAGE INPUT_ROOT OUTPUT_ROOT EXPECTED_VERSION
export FASTEMBEDR_IMAGE_SHA256 JSS_CAMPAIGN_ID JSS_CAMPAIGN_DIR JSS_LEDGER
export FASTEMBEDR_DLL_SHA256
export FASTEMBEDR_SUITE_MANIFEST_SHA256
export JSS_RETRY_SECONDS="${JSS_RETRY_SECONDS:-60}"
export JSS_MAX_SUBMIT_ATTEMPTS="${JSS_MAX_SUBMIT_ATTEMPTS:-720}"
export FULL_CUDA_PAIR="${FULL_CUDA_PAIR:-FALSE}"
export TIMING_REPS="${TIMING_REPS:-5}"
export INCLUDE_NOMAD="${INCLUDE_NOMAD:-FALSE}"
NOMAD_IDENTITY=not_requested
LAUNCH_PHASE=nomad_identity
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

LAUNCH_PHASE=campaign_ledger
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
package_source_commit=$PACKAGE_SOURCE_COMMIT
source_archive_sha256=$SOURCE_SHA256
local_patch_sha256=$LOCAL_PATCH_SHA256
suite_manifest_sha256=$FASTEMBEDR_SUITE_MANIFEST_SHA256
suite_manifest=$JSS_CAMPAIGN_DIR/source_FILES.sha256
benchmark_source_archive=$JSS_CAMPAIGN_DIR/benchmark_source.tar.gz
benchmark_source_archive_sha256=$BENCHMARK_SOURCE_ARCHIVE_SHA256
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

LAUNCH_PHASE=controller_submission
CONTROLLER_JOB="$(campaign_submit_job \
  controller "controller_$JSS_STAGE" '' "$CONTROLLER" '' \
  "$JSS_STAGE")"
campaign_record_stage launcher submitted "controller=$CONTROLLER_JOB"
LAUNCH_PHASE=complete

cat <<EOF
Started staged fastEmbedR JSS campaign.
  package:    fastEmbedR $EXPECTED_VERSION
  image SHA:  $FASTEMBEDR_IMAGE_SHA256
  DLL SHA:    $FASTEMBEDR_DLL_SHA256
  source:     $PACKAGE_SOURCE_COMMIT
  archive:    $SOURCE_SHA256
  suite SHA:  $FASTEMBEDR_SUITE_MANIFEST_SHA256
  suite tar:  $BENCHMARK_SOURCE_ARCHIVE_SHA256
  campaign:   $JSS_CAMPAIGN_ID
  controller: $CONTROLLER_JOB
  ledger:     $JSS_LEDGER
  stages:     $JSS_CAMPAIGN_DIR/stages.tsv
  failures:   $JSS_CAMPAIGN_DIR/failures.tsv
  results:    $OUTPUT_ROOT
  method limit: $METHOD_TIMEOUT_SECONDS seconds (2 hours)

Monitor with:
  squeue -u \"$USER\"
  tail -f $BASE_DIR/benchmark_logs/feR_JSS_ctl_${CONTROLLER_JOB}.out
EOF
