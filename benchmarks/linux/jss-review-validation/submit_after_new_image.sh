#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
PREFLIGHT_ROOT="${PREFLIGHT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
FOLLOW_UP="$SUITE/slurm/run_after_image_preflights_cpu1.sh"

cd "$BASE_DIR"
mkdir -p benchmark_logs "$PREFLIGHT_ROOT"

[[ -f "$IMAGE" ]] || {
  echo "Missing rebuilt image: $IMAGE" >&2
  exit 1
}

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

CPU_JOB="$(sbatch --parsable "$SUITE/slurm/run_preflight_cpu.sh")"
CUDA_JOB="$(sbatch --parsable "$SUITE/slurm/run_preflight_cuda.sh")"
DEPENDENCY="afterany:$CPU_JOB:$CUDA_JOB"
EXPORTS="ALL,BASE_DIR=$BASE_DIR,SUITE=$SUITE,IMAGE=$IMAGE"
EXPORTS="$EXPORTS,EXPECTED_VERSION=$EXPECTED_VERSION"
EXPORTS="$EXPORTS,PREFLIGHT_ROOT=$PREFLIGHT_ROOT"
FOLLOW_UP_JOB="$(sbatch --parsable --dependency="$DEPENDENCY" \
  --export="$EXPORTS" "$FOLLOW_UP")"

cat <<EOF
Submitted rebuilt-image validation and staged campaign handoff.
  CPU preflight:    $CPU_JOB
  CUDA preflight:   $CUDA_JOB
  verification job: $FOLLOW_UP_JOB

The verification job uses afterany so that it can report either preflight
failure. It starts the campaign only when both strict preflights pass.

Monitor with:
  squeue -u "$USER"
  tail -f $BASE_DIR/benchmark_logs/feR_JSS_image_${FOLLOW_UP_JOB}.out
EOF
