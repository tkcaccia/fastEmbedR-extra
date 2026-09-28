#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=128G
#SBATCH --time=48:00:00
#SBATCH --array=0-10%4
#SBATCH --job-name=feR_JSS_full_quality
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_full_quality_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_full_quality_%A_%a.err
set -euo pipefail
SUITE="${SUITE:-/scratch/firenze/NN/benchmark_scripts/fastembedr_jss_review_validation}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
DATA_ROOT="${DATA_ROOT:-$BASE_DIR/Data}"
DATASETS=(
  COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST
  imagenet MetRef mass41 TabulaMuris Macosko2015_retina
)
DATASET="${DATASETS[${SLURM_ARRAY_TASK_ID:?array task ID required}]}"
source "$SUITE/common/container_runtime.sh"
source "$SUITE/common/campaign_submit.sh"
campaign_verify_suite_revision
CONTAINER="$(command -v apptainer || command -v singularity)"
"$CONTAINER" exec --cleanenv --bind "$BASE_DIR:$BASE_DIR" \
  --pwd "$BASE_DIR" "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
  --env "INCLUDE_NOMAD=${INCLUDE_NOMAD:-FALSE}" \
  "$IMAGE" "$FASTEMBEDR_RSCRIPT" \
  "$SUITE/common/score_full_cuda_pair.R" \
  "--dataset=$DATASET" "--data-root=$DATA_ROOT" \
  "--input-root=$INPUT_ROOT" "--output-root=$OUTPUT_ROOT"
for family in tsne umap; do
  "$CONTAINER" exec --cleanenv --bind "$BASE_DIR:$BASE_DIR" \
    --pwd "$BASE_DIR" "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
    --env "INCLUDE_NOMAD=${INCLUDE_NOMAD:-FALSE}" \
    "$IMAGE" "$FASTEMBEDR_RSCRIPT" \
    "$SUITE/common/plot_cuda_pair.R" \
    "--dataset=$DATASET" "--family=$family" \
    "--input-root=$INPUT_ROOT" "--output-root=$OUTPUT_ROOT"
done
