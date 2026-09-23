#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --job-name=feR_clust_aggregate
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_clust_aggregate_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_clust_aggregate_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
SCRIPT="${SCRIPT:-$BASE_DIR/benchmark_scripts/hpc_clustering/aggregate_clustering_validation.R}"
CONTAINER="$(command -v apptainer || command -v singularity || true)"

mkdir -p "$BASE_DIR/benchmark_logs"
[[ -n "$CONTAINER" ]] || { echo "apptainer/singularity was not found" >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "Missing image: $IMAGE" >&2; exit 1; }
[[ -f "$SCRIPT" ]] || { echo "Missing aggregator: $SCRIPT" >&2; exit 1; }

"$CONTAINER" exec --cleanenv \
  --bind "$BASE_DIR:$BASE_DIR" \
  --pwd "$BASE_DIR" \
  "$IMAGE" \
  /opt/conda/bin/Rscript "$SCRIPT" \
    --base-dir="$BASE_DIR"
