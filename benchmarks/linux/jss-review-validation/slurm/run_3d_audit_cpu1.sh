#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=01:00:00
#SBATCH --job-name=feR_JSS_3d_audit
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_3d_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_3d_audit_%j.err
set -euo pipefail

: "${SUITE:?suite path required}"
: "${OUTPUT_ROOT:?result path required}"
: "${IMAGE:?image path required}"
source "$SUITE/common/container_runtime.sh"
CONTAINER="$(command -v apptainer || command -v singularity)"
"$CONTAINER" exec --cleanenv \
  --bind "$BASE_DIR:$BASE_DIR" --pwd "$BASE_DIR" \
  "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
  --env "OUTPUT_ROOT=$OUTPUT_ROOT" \
  "$IMAGE" "$FASTEMBEDR_RSCRIPT" "$SUITE/common/audit_3d.R"
