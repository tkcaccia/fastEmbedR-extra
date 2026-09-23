#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=128G
#SBATCH --time=48:00:00
#SBATCH --job-name=feR_clust_cpu4
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_clust_cpu4_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_clust_cpu4_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
SCRIPT="${SCRIPT:-$BASE_DIR/benchmark_scripts/hpc_clustering/benchmark_clustering_validation.R}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)_${SLURM_JOB_ID:-local}}"
OUT_DIR="${OUT_DIR:-$BASE_DIR/fastEmbedR-results/clustering_validation/cpu4/$RUN_ID}"
CONTAINER="$(command -v apptainer || command -v singularity || true)"

mkdir -p "$BASE_DIR/benchmark_logs" "$OUT_DIR"
[[ -n "$CONTAINER" ]] || { echo "apptainer/singularity was not found" >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "Missing image: $IMAGE" >&2; exit 1; }
[[ -f "$SCRIPT" ]] || { echo "Missing benchmark: $SCRIPT" >&2; exit 1; }

"$CONTAINER" exec --cleanenv \
  --bind "$BASE_DIR:$BASE_DIR" \
  --pwd "$BASE_DIR" \
  --env OMP_NUM_THREADS=4 \
  --env OPENBLAS_NUM_THREADS=4 \
  --env MKL_NUM_THREADS=4 \
  --env RCPP_PARALLEL_NUM_THREADS=4 \
  "$IMAGE" \
  /opt/conda/bin/Rscript "$SCRIPT" \
    --base-dir="$BASE_DIR" \
    --data-root="$BASE_DIR/Data" \
    --input-root="$BASE_DIR/fastEmbedR-input/clustering" \
    --backend-group=cpu \
    --threads=4 \
    --seeds=4,17,42 \
    --k=30 \
    --max-n=100000 \
    --out-dir="$OUT_DIR"
