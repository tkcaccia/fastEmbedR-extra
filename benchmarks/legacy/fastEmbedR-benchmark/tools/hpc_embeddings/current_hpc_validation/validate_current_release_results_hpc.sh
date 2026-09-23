#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --job-name=feR_release_gate
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_release_gate_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_release_gate_%j.err

set -euo pipefail

BASE_DIR=/scratch/firenze/NN
BUNDLE_DIR="${BASE_DIR}/current_fastembedr_validation"
RUN_ID="${FASTEMBEDR_RUN_ID:?FASTEMBEDR_RUN_ID is required}"
RUN_ROOT="${BASE_DIR}/fastEmbedR-results/${RUN_ID}"
IDENTITY="${BUNDLE_DIR}/validated_release_identity.env"
IMAGE="${BASE_DIR}/singularity/fastembedr_cuda.sif"
CONTAINER="$(command -v apptainer || command -v singularity || true)"

[[ -n "${CONTAINER}" ]] || { echo "apptainer/singularity is unavailable" >&2; exit 1; }
[[ -f "${IDENTITY}" ]] || { echo "Missing validated identity: ${IDENTITY}" >&2; exit 1; }

"${CONTAINER}" exec \
  --bind "${BASE_DIR}:${BASE_DIR}" \
  --pwd "${BUNDLE_DIR}" \
  "${IMAGE}" \
  /opt/conda/bin/Rscript "${BUNDLE_DIR}/validate_release_results.R" \
  --run-root="${RUN_ROOT}" \
  --identity="${IDENTITY}"

echo "Release result identity validated: ${RUN_ROOT}"
