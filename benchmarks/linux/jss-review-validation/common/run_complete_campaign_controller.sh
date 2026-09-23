#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
INPUT_ROOT="${INPUT_ROOT:?INPUT_ROOT is required}"
OUTPUT_ROOT="${OUTPUT_ROOT:?OUTPUT_ROOT is required}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
FASTEMBEDR_IMAGE_SHA256="${FASTEMBEDR_IMAGE_SHA256:?image checksum required}"
JSS_CAMPAIGN_ID="${JSS_CAMPAIGN_ID:?campaign ID required}"
JSS_CAMPAIGN_DIR="${JSS_CAMPAIGN_DIR:?campaign directory required}"
JSS_LEDGER="${JSS_LEDGER:?campaign ledger required}"
JSS_STAGE="${JSS_STAGE:?controller stage required}"
CONTROLLER="$SUITE/slurm/run_complete_campaign_controller_cpu1.sh"

source "$SUITE/common/campaign_submit.sh"
campaign_require_environment
campaign_init_ledger

NEXT_STAGE=""
WORKER_LABELS=()
WORKER_SCRIPTS=()
WORKER_ARRAYS=()

add_worker() {
  WORKER_LABELS+=("$1")
  WORKER_SCRIPTS+=("$2")
  WORKER_ARRAYS+=("${3:-}")
}

case "$JSS_STAGE" in
  shared_inputs)
    NEXT_STAGE=affinity_scaling
    add_worker precompute "$SUITE/slurm/run_precompute_cpu12.sh" '0-10%11'
    add_worker longrun_inputs \
      "$SUITE/slurm/run_tsne_longrun_precompute_cpu12.sh" '0-3%4'
    ;;
  affinity_scaling)
    NEXT_STAGE=support_cpu
    add_worker affinity "$SUITE/slurm/run_affinity_cpu12.sh" '0-10%5'
    add_worker scaling_1t "$SUITE/slurm/run_scaling_cpu1.sh" '0-3%4'
    add_worker scaling_2t "$SUITE/slurm/run_scaling_cpu2.sh" '0-3%4'
    add_worker scaling_4t "$SUITE/slurm/run_scaling_cpu4.sh" '0-3%4'
    add_worker scaling_8t "$SUITE/slurm/run_scaling_cpu8.sh" '0-3%4'
    add_worker scaling_12t "$SUITE/slurm/run_scaling_cpu12.sh" '0-3%4'
    ;;
  support_cpu)
    NEXT_STAGE=support_cuda
    add_worker support_cpu "$SUITE/slurm/run_support_cpu4.sh" '0-21%22'
    ;;
  support_cuda)
    NEXT_STAGE=recall_quality
    add_worker support_cuda "$SUITE/slurm/run_support_cuda.sh" '0-21%5'
    ;;
  recall_quality)
    NEXT_STAGE=transform_cpu
    add_worker recall_quality_cpu \
      "$SUITE/slurm/run_recall_quality_cpu4_compact.sh" '0-10%11'
    add_worker recall_quality_cuda \
      "$SUITE/slurm/run_recall_quality_cuda_compact.sh" '0-10%5'
    ;;
  transform_cpu)
    NEXT_STAGE=transform_cuda
    add_worker transform_cpu "$SUITE/slurm/run_transform_cpu4.sh" '0-21%22'
    ;;
  transform_cuda)
    NEXT_STAGE=landmark_cpu
    add_worker transform_cuda "$SUITE/slurm/run_transform_cuda.sh" '0-21%5'
    ;;
  landmark_cpu)
    NEXT_STAGE=landmark_cuda
    add_worker landmark_cpu \
      "$SUITE/slurm/run_landmark_reconstruction_cpu4.sh" '0-21%22'
    ;;
  landmark_cuda)
    NEXT_STAGE=pca_cpu_1
    add_worker landmark_cuda \
      "$SUITE/slurm/run_landmark_reconstruction_cuda.sh" '0-21%5'
    ;;
  pca_cpu_1)
    NEXT_STAGE=pca_cpu_3
    add_worker pca_cpu_1t "$SUITE/slurm/run_pca_cpu1.sh" '0-21%22'
    add_worker pca_cpu_4t "$SUITE/slurm/run_pca_cpu4.sh" '0-21%22'
    ;;
  pca_cpu_2)
    NEXT_STAGE=pca_cpu_3
    add_worker pca_cpu_4t "$SUITE/slurm/run_pca_cpu4.sh" '0-21%22'
    ;;
  pca_cpu_3)
    NEXT_STAGE=pca_cuda
    add_worker pca_cpu_12t "$SUITE/slurm/run_pca_cpu12.sh" '0-21%16'
    ;;
  pca_cuda)
    NEXT_STAGE=pca_accuracy_cpu
    add_worker pca_cuda "$SUITE/slurm/run_pca_cuda.sh" '0-21%5'
    ;;
  pca_accuracy_cpu)
    NEXT_STAGE=pca_accuracy_cuda
    add_worker pca_accuracy_cpu \
      "$SUITE/slurm/run_pca_accuracy_cpu4.sh" '0-21%22'
    ;;
  pca_accuracy_cuda)
    NEXT_STAGE=clustering_precompute
    add_worker pca_accuracy_cuda \
      "$SUITE/slurm/run_pca_accuracy_cuda.sh" '0-21%5'
    ;;
  clustering_precompute)
    NEXT_STAGE=clustering_cpu
    add_worker clustering_precompute \
      "$SUITE/slurm/run_clustering_precompute_cpu4.sh" '0-10%11'
    ;;
  clustering_cpu)
    NEXT_STAGE=clustering_cuda
    add_worker clustering_cpu \
      "$SUITE/slurm/run_clustering_cpu4.sh" '0-10%11'
    ;;
  clustering_cuda)
    NEXT_STAGE=knn_sensitivity
    add_worker clustering_cuda \
      "$SUITE/slurm/run_clustering_cuda.sh" '0-10%4'
    ;;
  knn_sensitivity)
    NEXT_STAGE=components
    add_worker knn_sensitivity_cpu \
      "$SUITE/slurm/run_knn_sensitivity_cpu4.sh" '0-10%11'
    add_worker knn_sensitivity_cuda \
      "$SUITE/slurm/run_knn_sensitivity_cuda.sh" '0-10%5'
    ;;
  components)
    NEXT_STAGE=longrun_cpu_1
    add_worker components_cpu "$SUITE/slurm/run_components_cpu12.sh"
    add_worker components_cuda "$SUITE/slurm/run_components_cuda.sh"
    ;;
  longrun_cpu_1)
    NEXT_STAGE=longrun_cpu_2
    add_worker longrun_cpu_1 \
      "$SUITE/slurm/run_tsne_longrun_cpu4.sh" '0-23%24'
    ;;
  longrun_cpu_2)
    NEXT_STAGE=longrun_cpu_3
    add_worker longrun_cpu_2 \
      "$SUITE/slurm/run_tsne_longrun_cpu4.sh" '24-47%24'
    ;;
  longrun_cpu_3)
    NEXT_STAGE=longrun_cuda_1
    add_worker longrun_cpu_3 \
      "$SUITE/slurm/run_tsne_longrun_cpu4.sh" '48-71%24'
    ;;
  longrun_cuda_1)
    NEXT_STAGE=longrun_cuda_2
    add_worker longrun_cuda_1 \
      "$SUITE/slurm/run_tsne_longrun_cuda.sh" '0-23%5'
    ;;
  longrun_cuda_2)
    NEXT_STAGE=longrun_cuda_3
    add_worker longrun_cuda_2 \
      "$SUITE/slurm/run_tsne_longrun_cuda.sh" '24-47%5'
    ;;
  longrun_cuda_3)
    NEXT_STAGE=longrun_final
    add_worker longrun_cuda_3 \
      "$SUITE/slurm/run_tsne_longrun_cuda.sh" '48-71%5'
    ;;
  longrun_final)
    NEXT_STAGE=longrun_threads
    add_worker longrun_final_cpu \
      "$SUITE/slurm/run_tsne_longrun_final_cpu4.sh" '0-7%8'
    add_worker longrun_final_cuda \
      "$SUITE/slurm/run_tsne_longrun_final_cuda.sh" '0-7%5'
    ;;
  longrun_threads)
    NEXT_STAGE=longrun_python
    add_worker longrun_threads_1t \
      "$SUITE/slurm/run_tsne_longrun_threads_cpu1.sh" '0-11%11'
    add_worker longrun_threads_12t \
      "$SUITE/slurm/run_tsne_longrun_threads_cpu12.sh" '0-11%11'
    ;;
  longrun_python)
    NEXT_STAGE=timing
    add_worker longrun_python \
      "$SUITE/slurm/run_tsne_longrun_python_cpu4.sh" '0-31%32'
    ;;
  timing)
    NEXT_STAGE=aggregate
    add_worker timing_cpu "$SUITE/slurm/run_tsne_timing_cpu4.sh" '0-3%4'
    add_worker timing_cuda "$SUITE/slurm/run_tsne_timing_cuda.sh" '0-3%4'
    add_worker timing_python \
      "$SUITE/slurm/run_tsne_timing_python_cpu4.sh" '0-3%4'
    ;;
  aggregate)
    NEXT_STAGE=final_audit
    add_worker aggregate "$SUITE/slurm/run_aggregate_cpu1.sh"
    ;;
  final_audit)
    bash "$SUITE/common/run_campaign_final_audit.sh"
    exit $?
    ;;
  *)
    echo "Unknown campaign stage: $JSS_STAGE" >&2
    exit 2
    ;;
esac

WORKER_IDS=()
for index in "${!WORKER_LABELS[@]}"; do
  WORKER_IDS+=("$(campaign_submit_job \
    worker "${WORKER_LABELS[$index]}" '' \
    "${WORKER_SCRIPTS[$index]}" "${WORKER_ARRAYS[$index]}")")
done

DEPENDENCY="$(campaign_afterany_dependency "${WORKER_IDS[@]}")"
NEXT_JOB="$(campaign_submit_job \
  controller "controller_$NEXT_STAGE" "$DEPENDENCY" \
  "$CONTROLLER" '' "$NEXT_STAGE")"

echo "Stage $JSS_STAGE submitted workers: ${WORKER_IDS[*]}"
echo "Next stage $NEXT_STAGE controller: $NEXT_JOB ($DEPENDENCY)"
