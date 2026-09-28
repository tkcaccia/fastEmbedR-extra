#!/usr/bin/env bash
set -euo pipefail

SUITE="${SUITE:-/scratch/firenze/NN/benchmark_scripts/fastembedr_jss_review_validation}"
DATASETS=(
  COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST
  imagenet MetRef mass41 TabulaMuris Macosko2015_retina
)
PRIORITY=(7 1 0 5 2 8 9 10 4 3 6)
ARRAY_ID="${SLURM_ARRAY_TASK_ID:?array task ID required}"
[[ "$ARRAY_ID" =~ ^[0-9]+$ ]] || exit 2
(( ARRAY_ID < 44 )) || exit 2
DATASET_INDEX="${PRIORITY[$((ARRAY_ID / 4))]}"
METHOD_INDEX="$((ARRAY_ID % 4))"
TASK_ID="$((DATASET_INDEX * 2 + METHOD_INDEX / 2))"
MODE=r_cuda
(( METHOD_INDEX % 2 == 0 )) || MODE=python_cuda
echo "Full-source CUDA: ${DATASETS[$DATASET_INDEX]} method=$METHOD_INDEX"
COMPARATOR_TASK_ID="$TASK_ID" FULL_CUDA_PAIR=TRUE \
  bash "$SUITE/common/run_comparator_task.sh" "$MODE"
