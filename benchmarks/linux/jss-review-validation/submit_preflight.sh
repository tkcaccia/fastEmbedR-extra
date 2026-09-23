#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation"
cd "$BASE_DIR"
mkdir -p benchmark_logs fastEmbedR-results/jss_validation

IDENTITY_ROOT="$BASE_DIR/fastEmbedR-results/jss_validation/identity"
if [[ -d "$IDENTITY_ROOT" ]]; then
  ARCHIVE_ROOT="$BASE_DIR/fastEmbedR-results/jss_validation/preflight_archive"
  ARCHIVE="$ARCHIVE_ROOT/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$ARCHIVE_ROOT"
  mv "$IDENTITY_ROOT" "$ARCHIVE"
  echo "Archived previous preflight evidence at $ARCHIVE"
fi

CPU_JOB="$(sbatch --parsable "$SUITE/slurm/run_preflight_cpu.sh")"
CUDA_JOB="$(sbatch --parsable "$SUITE/slurm/run_preflight_cuda.sh")"

cat <<EOF
Submitted only the strict fastEmbedR preflights.
  CPU preflight:  $CPU_JOB
  CUDA preflight: $CUDA_JOB

Wait for both jobs to finish, then run:
  bash $SUITE/verify_preflight.sh
EOF
