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
methods_per_large=4
if [[ "${INCLUDE_NOMAD:-FALSE}" == TRUE ]]; then
  methods_per_large=5
fi
(( ARRAY_ID < 9 + 2 * methods_per_large )) || exit 2
if (( ARRAY_ID < 9 )); then
  DATASET_INDEX="${PRIORITY[$ARRAY_ID]}"
  method_indices=(0 1 2 3)
  if (( methods_per_large == 5 )); then
    method_indices+=(4)
  fi
else
  large_offset="$((ARRAY_ID - 9))"
  DATASET_INDEX="${PRIORITY[$((9 + large_offset / methods_per_large))]}"
  method_indices=("$((large_offset % methods_per_large))")
fi
DATASET="${DATASETS[$DATASET_INDEX]}"
STATUS_DIR="${OUTPUT_ROOT:?OUTPUT_ROOT is required}/scheduler_status/full_cuda_pairs"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/${SLURM_JOB_ID:-local}_${ARRAY_ID}.csv"
printf 'dataset,mode,method,task_id,status,exit_code,elapsed_sec\n' \
  > "$STATUS_FILE"
failures=0

for method_index in "${method_indices[@]}"; do
  if (( method_index == 4 )); then
    task_id="$DATASET_INDEX"
    mode=python_nomad
    method=nomad
  else
    task_id="$((DATASET_INDEX * 2 + method_index / 2))"
    mode=r_cuda
    (( method_index % 2 == 0 )) || mode=python_cuda
    method=tsne
    (( method_index < 2 )) || method=umap
  fi
  started="$(date +%s)"
  echo "Full-source CUDA: $DATASET $mode $method"
  if COMPARATOR_TASK_ID="$task_id" FULL_CUDA_PAIR=TRUE \
      bash "$SUITE/common/run_comparator_task.sh" "$mode"; then
    code=0
    status=completed
  else
    code=$?
    status=failed
    failures=$((failures + 1))
  fi
  printf '%s,%s,%s,%s,%s,%s,%s\n' "$DATASET" "$mode" \
    "$method" "$task_id" "$status" "$code" \
    "$(( $(date +%s) - started ))" >> "$STATUS_FILE"
done
(( failures == 0 )) || exit 1
