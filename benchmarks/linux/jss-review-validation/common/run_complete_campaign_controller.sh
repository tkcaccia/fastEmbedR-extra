#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
INPUT_ROOT="${INPUT_ROOT:?INPUT_ROOT is required}"
OUTPUT_ROOT="${OUTPUT_ROOT:?OUTPUT_ROOT is required}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"
FASTEMBEDR_IMAGE_SHA256="${FASTEMBEDR_IMAGE_SHA256:?image checksum required}"
: "${FASTEMBEDR_DLL_SHA256:?package DLL checksum required}"
: "${FASTEMBEDR_SUITE_MANIFEST_SHA256:?suite checksum required}"
JSS_CAMPAIGN_ID="${JSS_CAMPAIGN_ID:?campaign ID required}"
JSS_CAMPAIGN_DIR="${JSS_CAMPAIGN_DIR:?campaign directory required}"
JSS_LEDGER="${JSS_LEDGER:?campaign ledger required}"
JSS_STAGE="${JSS_STAGE:?controller stage required}"
CONTROLLER="$SUITE/slurm/run_complete_campaign_controller_cpu1.sh"

source "$SUITE/common/campaign_submit.sh"
campaign_require_environment
campaign_verify_suite_revision
campaign_init_ledger
trap 'campaign_record_controller_failure "$?"' ERR
if [[ "$JSS_STAGE" != comparators_cuda ]]; then
  campaign_record_previous_stage
fi
campaign_record_stage "$JSS_STAGE" started \
  "controller=${SLURM_JOB_ID:-local}"

NEXT_STAGE=""
PARALLEL_STAGE=""
SECOND_PARALLEL_STAGE=""
WORKER_LABELS=()
WORKER_SCRIPTS=()
WORKER_ARRAYS=()

add_worker() {
  WORKER_LABELS+=("$1")
  WORKER_SCRIPTS+=("$2")
  WORKER_ARRAYS+=("${3:-}")
}

case "$JSS_STAGE" in
  full_precompute)
    NEXT_STAGE=full_inputs
    add_worker full_precompute \
      "$SUITE/slurm/run_full_precompute_cpu1.sh" '0-10%4'
    ;;
  full_inputs)
    NEXT_STAGE=full_pairs
    add_worker full_inputs \
      "$SUITE/slurm/run_full_inputs_cpu1.sh" '0-10%4'
    ;;
  full_pairs)
    NEXT_STAGE=full_quality
    if [[ "${INCLUDE_NOMAD:-FALSE}" == TRUE ]]; then
      full_array='0-20%2'
    else
      full_array='0-18%2'
    fi
    add_worker full_pairs \
      "$SUITE/slurm/run_full_pairs_cuda.sh" "$full_array"
    ;;
  full_quality)
    NEXT_STAGE=full_final_audit
    add_worker full_quality \
      "$SUITE/slurm/run_full_quality_cpu1.sh" '0-10%4'
    ;;
  full_final_audit)
    if bash "$SUITE/common/run_full_final_audit.sh"; then
      campaign_record_stage full_final_audit completed 'status=PASS'
      exit 0
    fi
    campaign_record_stage full_final_audit completed 'status=FAIL'
    campaign_record_controller_failure 1
    exit 1
    ;;
  comparator_preflight)
    NEXT_STAGE=shared_inputs
    add_worker comparator_preflight_cpu \
      "$SUITE/slurm/run_comparator_preflight_cpu.sh"
    add_worker comparator_preflight_cuda \
      "$SUITE/slurm/run_comparator_preflight_cuda.sh"
    ;;
  shared_inputs)
    NEXT_STAGE=comparator_inputs
    add_worker precompute "$SUITE/slurm/run_precompute_cpu12.sh" '0-10%11'
    add_worker longrun_inputs \
      "$SUITE/slurm/run_tsne_longrun_precompute_cpu12.sh" '0-3%4'
    ;;
  comparator_inputs)
    NEXT_STAGE=affinity_scaling
    PARALLEL_STAGE=comparators_cuda
    SECOND_PARALLEL_STAGE=file_backed
    add_worker comparator_inputs \
      "$SUITE/slurm/run_comparator_inputs_cpu12.sh" '0-10%11'
    ;;
  file_backed)
    NEXT_STAGE=file_backed_audit
    add_worker file_backed_matched \
      "$SUITE/slurm/run_file_backed_matched_cpu4.sh" '0-3%4'
    add_worker file_backed_scaling \
      "$SUITE/slurm/run_file_backed_scaling_cuda.sh" '0-5%2'
    add_worker file_backed_boundary \
      "$SUITE/slurm/run_file_backed_boundary_cpu4.sh" '0-1%2'
    add_worker file_backed_full \
      "$SUITE/slurm/run_file_backed_full_cuda.sh"
    add_worker file_backed_multi \
      "$SUITE/slurm/run_file_backed_multi_cuda.sh"
    add_worker file_backed_recovery \
      "$SUITE/slurm/run_file_backed_recovery_cpu4.sh"
    add_worker file_backed_recovery_cuda \
      "$SUITE/slurm/run_file_backed_recovery_cuda.sh"
    ;;
  file_backed_audit)
    NEXT_STAGE=file_backed_done
    add_worker file_backed_audit \
      "$SUITE/slurm/run_file_backed_audit_cpu1.sh"
    ;;
  cuda_pairs)
    NEXT_STAGE=support_cuda
    add_worker cuda_pairs \
      "$SUITE/slurm/run_cuda_pairs.sh" '0-10%2'
    ;;
  affinity_scaling)
    NEXT_STAGE=scaling
    add_worker affinity "$SUITE/slurm/run_affinity_cpu12.sh" '0-10%5'
    ;;
  scaling)
    NEXT_STAGE=support_cpu
    add_worker scaling "$SUITE/slurm/run_scaling_cpu12.sh" '0-3%4'
    ;;
  support_cpu)
    NEXT_STAGE=support_sweep_cpu
    add_worker support_cpu "$SUITE/slurm/run_support_cpu4.sh" '0-7%8'
    ;;
  support_cuda)
    NEXT_STAGE=support_sweep_cuda
    add_worker support_cuda "$SUITE/slurm/run_support_cuda.sh" '0-3%4'
    ;;
  support_sweep_cpu)
    NEXT_STAGE=recall_quality_cpu
    add_worker support_sweep_cpu \
      "$SUITE/slurm/run_support_sweep_cpu4.sh" '0-15%16'
    ;;
  support_sweep_cuda)
    NEXT_STAGE=recall_quality_cuda
    add_worker support_sweep_cuda \
      "$SUITE/slurm/run_support_sweep_cuda.sh" '0-3%4'
    ;;
  recall_quality_cpu)
    NEXT_STAGE=transform_cpu
    add_worker recall_quality_cpu \
      "$SUITE/slurm/run_recall_quality_cpu4_compact.sh" '0-10%11'
    ;;
  recall_quality_cuda)
    NEXT_STAGE=transform_cuda
    add_worker recall_quality_cuda \
      "$SUITE/slurm/run_recall_quality_cuda_compact.sh" '0-10%5'
    ;;
  transform_cpu)
    NEXT_STAGE=landmark_cpu
    add_worker transform_cpu "$SUITE/slurm/run_transform_cpu4.sh" '0-21%22'
    ;;
  transform_cuda)
    NEXT_STAGE=landmark_memory_cuda
    add_worker transform_landmark_cuda \
      "$SUITE/slurm/run_transform_landmark_cuda_bundle.sh" '0-10%5'
    ;;
  landmark_cpu)
    NEXT_STAGE=landmark_memory_cpu
    add_worker landmark_cpu \
      "$SUITE/slurm/run_landmark_reconstruction_cpu4.sh" '0-21%22'
    ;;
  landmark_memory_cpu)
    NEXT_STAGE=pca_cpu_1
    add_worker landmark_memory_cpu \
      "$SUITE/slurm/run_landmark_memory_cpu4.sh" '0-43%40'
    ;;
  landmark_memory_cuda)
    NEXT_STAGE=pca_cuda
    add_worker landmark_memory_cuda \
      "$SUITE/slurm/run_landmark_memory_cuda.sh" '0-10%4'
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
    NEXT_STAGE=pca_accuracy_cpu
    add_worker pca_cpu_12t "$SUITE/slurm/run_pca_cpu12.sh" '0-21%16'
    ;;
  pca_cuda)
    NEXT_STAGE=knn_sensitivity_cuda
    add_worker pca_accuracy_cuda \
      "$SUITE/slurm/run_pca_accuracy_cuda_bundle.sh" '0-10%5'
    ;;
  pca_accuracy_cpu)
    NEXT_STAGE=clustering_precompute
    add_worker pca_accuracy_cpu \
      "$SUITE/slurm/run_pca_accuracy_cpu4.sh" '0-21%22'
    ;;
  clustering_precompute)
    NEXT_STAGE=clustering_cpu
    add_worker clustering_precompute \
      "$SUITE/slurm/run_clustering_precompute_cpu4.sh" '0-3%4'
    ;;
  clustering_cpu)
    NEXT_STAGE=clustering_scale_cpu
    add_worker clustering_cpu \
      "$SUITE/slurm/run_clustering_cpu4.sh" '0-3%4'
    ;;
  clustering_scale_cpu)
    NEXT_STAGE=knn_sensitivity_cpu
    add_worker clustering_scale_cpu \
      "$SUITE/slurm/run_clustering_scale_cpu4.sh"
    ;;
  clustering_cuda)
    NEXT_STAGE=clustering_scale_cuda
    add_worker clustering_cuda \
      "$SUITE/slurm/run_clustering_cuda.sh" '0-3%4'
    ;;
  clustering_scale_cuda)
    NEXT_STAGE=aggregate
    add_worker clustering_scale_cuda \
      "$SUITE/slurm/run_clustering_scale_cuda.sh"
    ;;
  knn_sensitivity_cpu)
    NEXT_STAGE=components_cpu
    add_worker knn_sensitivity_cpu \
      "$SUITE/slurm/run_knn_sensitivity_cpu4.sh" '0-10%11'
    ;;
  knn_sensitivity_cuda)
    NEXT_STAGE=components_cuda
    add_worker knn_sensitivity_cuda \
      "$SUITE/slurm/run_knn_sensitivity_cuda.sh" '0-10%5'
    ;;
  components_cpu)
    NEXT_STAGE=longrun_cpu_1
    add_worker components_cpu "$SUITE/slurm/run_components_cpu12.sh"
    ;;
  components_cuda)
    NEXT_STAGE=longrun_cuda_1
    add_worker components_cuda "$SUITE/slurm/run_components_cuda.sh"
    ;;
  longrun_cpu_1)
    NEXT_STAGE=longrun_final_cpu
    add_worker longrun_cpu_1 \
      "$SUITE/slurm/run_tsne_longrun_cpu4.sh" '0-71%24'
    ;;
  longrun_cuda_1)
    NEXT_STAGE=gpu_done
    add_worker longrun_cuda_bundle \
      "$SUITE/slurm/run_tsne_longrun_cuda_bundle.sh" '0-3%4'
    ;;
  longrun_final_cpu)
    NEXT_STAGE=longrun_threads
    add_worker longrun_final_cpu \
      "$SUITE/slurm/run_tsne_longrun_final_cpu4.sh" '0-7%8'
    ;;
  longrun_threads)
    NEXT_STAGE=longrun_python
    add_worker longrun_threads_1t \
      "$SUITE/slurm/run_tsne_longrun_threads_cpu1.sh" '0-11%11'
    add_worker longrun_threads_12t \
      "$SUITE/slurm/run_tsne_longrun_threads_cpu12.sh" '0-11%11'
    ;;
  longrun_python)
    NEXT_STAGE=timing_cpu
    add_worker longrun_python \
      "$SUITE/slurm/run_tsne_longrun_python_cpu4.sh" '0-31%32'
    ;;
  timing_cpu)
    NEXT_STAGE=comparators_cpu
    add_worker timing_cpu "$SUITE/slurm/run_tsne_timing_cpu4.sh" '0-3%4'
    add_worker timing_python \
      "$SUITE/slurm/run_tsne_timing_python_cpu4.sh" '0-3%4'
    ;;
  comparators_cpu)
    NEXT_STAGE=cpu_done
    add_worker comparators_r \
      "$SUITE/slurm/run_comparators_r_cpu4.sh" '0-109%40'
    add_worker comparators_python_cpu \
      "$SUITE/slurm/run_comparators_python_cpu4.sh" '0-43%40'
    ;;
  comparators_cuda)
    NEXT_STAGE=cuda_pairs
    add_worker comparators_cuda_pca \
      "$SUITE/slurm/run_comparators_cuda_pca.sh" '0-10%2'
    ;;
  cpu_done|gpu_done|file_backed_done)
    campaign_record_stage "$JSS_STAGE" completed 'workers=finished'
    exec 9> "$JSS_CAMPAIGN_DIR/lane_join.lock"
    flock 9
    touch "$JSS_CAMPAIGN_DIR/$JSS_STAGE"
    if [[ -f "$JSS_CAMPAIGN_DIR/cpu_done" && \
          -f "$JSS_CAMPAIGN_DIR/gpu_done" && \
          -f "$JSS_CAMPAIGN_DIR/file_backed_done" ]]; then
      JOIN_JOB="$(campaign_submit_job controller \
        controller_clustering_cuda '' "$CONTROLLER" '' clustering_cuda)"
      campaign_record_stage "$JSS_STAGE" joined \
        "controller=$JOIN_JOB"
    fi
    exit 0
    ;;
  aggregate)
    NEXT_STAGE=final_audit
    add_worker aggregate "$SUITE/slurm/run_aggregate_cpu1.sh"
    ;;
  final_audit)
    if bash "$SUITE/common/run_campaign_final_audit.sh"; then
      campaign_record_stage final_audit completed 'status=PASS'
      exit 0
    fi
    campaign_record_stage final_audit completed 'status=FAIL'
    campaign_record_controller_failure 1
    exit 1
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

if [[ "$JSS_STAGE" == comparator_preflight ]]; then
  DEPENDENCY="afterok:$(IFS=:; echo "${WORKER_IDS[*]}")"
else
  DEPENDENCY="$(campaign_afterany_dependency "${WORKER_IDS[@]}")"
fi
NEXT_JOB="$(campaign_submit_job \
  controller "controller_$NEXT_STAGE" "$DEPENDENCY" \
  "$CONTROLLER" '' "$NEXT_STAGE")"
if [[ -n "$PARALLEL_STAGE" ]]; then
  PARALLEL_JOB="$(campaign_submit_job \
    controller "controller_$PARALLEL_STAGE" "$DEPENDENCY" \
    "$CONTROLLER" '' "$PARALLEL_STAGE")"
  campaign_record_stage "$JSS_STAGE" forked \
    "cpu=$NEXT_JOB cuda=$PARALLEL_JOB dependency=$DEPENDENCY"
fi
if [[ -n "$SECOND_PARALLEL_STAGE" ]]; then
  SECOND_JOB="$(campaign_submit_job \
    controller "controller_$SECOND_PARALLEL_STAGE" "$DEPENDENCY" \
    "$CONTROLLER" '' "$SECOND_PARALLEL_STAGE")"
  campaign_record_stage "$JSS_STAGE" forked \
    "file_backed=$SECOND_JOB dependency=$DEPENDENCY"
fi

echo "Stage $JSS_STAGE submitted workers: ${WORKER_IDS[*]}"
echo "Next stage $NEXT_STAGE controller: $NEXT_JOB ($DEPENDENCY)"
campaign_record_stage "$JSS_STAGE" submitted \
  "workers=${WORKER_IDS[*]} next=$NEXT_STAGE controller=$NEXT_JOB"
