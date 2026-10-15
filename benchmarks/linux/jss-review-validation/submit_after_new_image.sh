#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
PREFLIGHT_ROOT="${PREFLIGHT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
INCLUDE_NOMAD="${INCLUDE_NOMAD:-FALSE}"
if [[ -z "${CAMPAIGN_MODE:-}" ]]; then
  CAMPAIGN_MODE=complete
  [[ "$INCLUDE_NOMAD" == TRUE ]] && CAMPAIGN_MODE=full_cuda
fi
FOLLOW_UP="$SUITE/slurm/run_after_image_preflights_cpu1.sh"
[[ -f "$SUITE/common/campaign_submit.sh" ]] || {
  echo "Missing campaign submission helpers in $SUITE" >&2
  exit 1
}
source "$SUITE/common/campaign_submit.sh"
campaign_require_method_timeout || exit $?

case "$CAMPAIGN_MODE" in
  complete|full_cuda) ;;
  *) echo "CAMPAIGN_MODE must be complete or full_cuda." >&2; exit 2 ;;
esac
if [[ "$CAMPAIGN_MODE" == full_cuda ]]; then
  TIMING_REPS="${TIMING_REPS:-3}"
else
  TIMING_REPS="${TIMING_REPS:-5}"
fi
if [[ "$INCLUDE_NOMAD" == TRUE && "$CAMPAIGN_MODE" != full_cuda ]]; then
  echo "NOMAD requires CAMPAIGN_MODE=full_cuda." >&2
  exit 2
fi
[[ "$INCLUDE_NOMAD" == TRUE || "$INCLUDE_NOMAD" == FALSE ]] || {
  echo "INCLUDE_NOMAD must be TRUE or FALSE." >&2
  exit 2
}

cd "$BASE_DIR"
mkdir -p benchmark_logs "$PREFLIGHT_ROOT"

[[ -f "$IMAGE" ]] || {
  echo "Missing rebuilt image: $IMAGE" >&2
  exit 1
}
IMAGE_SHA256="$(sha256sum "$IMAGE" | awk '{print $1}')"
if ! awk -F, -v sha="$IMAGE_SHA256" \
  'NR > 1 && $1 == sha { found++ } END { exit(found == 1 ? 0 : 1) }' \
  "$SUITE/common/image_source_identity.csv"; then
  echo "Image checksum is not the validated source-locked build:" >&2
  echo "$IMAGE_SHA256" >&2
  exit 1
fi

bash "$SUITE/common/validate_slurm_resources.sh" "$SUITE"
(
  cd "$SUITE"
  sha256sum -c FILES.sha256
)

IDENTITY_ROOT="$PREFLIGHT_ROOT/identity"
if [[ -d "$IDENTITY_ROOT" ]]; then
  ARCHIVE_ROOT="$PREFLIGHT_ROOT/preflight_archive"
  ARCHIVE="$ARCHIVE_ROOT/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$ARCHIVE_ROOT"
  mv "$IDENTITY_ROOT" "$ARCHIVE"
  echo "Archived previous preflight evidence at $ARCHIVE"
fi

EXPORTS="ALL,BASE_DIR=$BASE_DIR,SUITE=$SUITE,IMAGE=$IMAGE"
EXPORTS="$EXPORTS,EXPECTED_VERSION=$EXPECTED_VERSION"
EXPORTS="$EXPORTS,PREFLIGHT_ROOT=$PREFLIGHT_ROOT"
EXPORTS="$EXPORTS,OUTPUT_ROOT=$PREFLIGHT_ROOT"
EXPORTS="$EXPORTS,CAMPAIGN_MODE=$CAMPAIGN_MODE"
EXPORTS="$EXPORTS,INCLUDE_NOMAD=$INCLUDE_NOMAD"
EXPORTS="$EXPORTS,METHOD_TIMEOUT_SECONDS=$METHOD_TIMEOUT_SECONDS"
EXPORTS="$EXPORTS,TIMING_REPS=$TIMING_REPS"
CPU_JOB="$(sbatch --parsable --export="$EXPORTS" \
  "$SUITE/slurm/run_preflight_cpu.sh")"
CUDA_JOB="$(sbatch --parsable --export="$EXPORTS" \
  "$SUITE/slurm/run_preflight_cuda.sh")"
DEPENDENCY="afterany:$CPU_JOB:$CUDA_JOB"
EXPORTS="$EXPORTS,CPU_PREFLIGHT_JOB=$CPU_JOB,CUDA_PREFLIGHT_JOB=$CUDA_JOB"
FOLLOW_UP_JOB="$(sbatch --parsable --dependency="$DEPENDENCY" \
  --export="$EXPORTS" "$FOLLOW_UP")"

cat <<EOF
Submitted strict preflights and automatic $CAMPAIGN_MODE campaign handoff.
  CPU preflight:    $CPU_JOB
  CUDA preflight:   $CUDA_JOB
  verification job: $FOLLOW_UP_JOB

The verification job uses afterany so that it can report either preflight
failure. It starts the campaign only when both strict preflights pass.

Monitor with:
  squeue -u "$USER"
  tail -f $BASE_DIR/benchmark_logs/feR_JSS_image_${FOLLOW_UP_JOB}.out
EOF
