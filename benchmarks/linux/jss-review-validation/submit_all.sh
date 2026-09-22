#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation"
cd "$BASE_DIR"
mkdir -p benchmark_logs fastEmbedR-input/jss_validation \
  fastEmbedR-results/jss_validation

if [[ "${FASTEMBEDR_ALLOW_LARGE_SUBMISSION:-FALSE}" != "TRUE" ]]; then
  cat >&2 <<EOF
The monolithic submission is disabled by default because its large arrays can
exceed the HPC QOS submission limit. Run submit_preflight.sh first, verify both
backends, and use submit_recall_quality_compact.sh or submit individual families.

Set FASTEMBEDR_ALLOW_LARGE_SUBMISSION=TRUE only when the account has sufficient
queued-task capacity and you intentionally want the complete campaign at once.
EOF
  exit 2
fi

bash "$SUITE/verify_preflight.sh"

submit() {
  local dependency="$1"
  local script="$2"
  if [[ -n "$dependency" ]]; then
    sbatch --parsable --dependency="$dependency" "$script"
  else
    sbatch --parsable "$script"
  fi
}

PRECOMPUTE="$(submit '' "$SUITE/slurm/run_precompute_cpu12.sh")"
LONGRUN_INPUT="$(submit '' \
  "$SUITE/slurm/run_tsne_longrun_precompute_cpu12.sh")"
AFFINITY="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_affinity_cpu12.sh")"
SUPPORT_CPU="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_support_cpu4.sh")"
SUPPORT_CUDA="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_support_cuda.sh")"
QUALITY_CPU="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_backend_quality_cpu4.sh")"
QUALITY_CUDA="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_backend_quality_cuda.sh")"
TRANSFORM_CPU="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_transform_cpu4.sh")"
TRANSFORM_CUDA="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_transform_cuda.sh")"
LANDMARK_CPU="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_landmark_reconstruction_cpu4.sh")"
LANDMARK_CUDA="$(submit "afterok:$PRECOMPUTE" \
  "$SUITE/slurm/run_landmark_reconstruction_cuda.sh")"
SCALING="$(submit '' \
  "$SUITE/slurm/run_scaling_cpu12.sh")"
PCA_CPU="$(submit '' \
  "$SUITE/slurm/run_pca_cpu12.sh")"
PCA_CUDA="$(submit '' \
  "$SUITE/slurm/run_pca_cuda.sh")"
PCA_ACCURACY_CPU="$(submit '' \
  "$SUITE/slurm/run_pca_accuracy_cpu4.sh")"
PCA_ACCURACY_CUDA="$(submit '' \
  "$SUITE/slurm/run_pca_accuracy_cuda.sh")"
KNN_OBSERVED_CPU="$(submit '' \
  "$SUITE/slurm/run_knn_observed_cpu4.sh")"
KNN_OBSERVED_CUDA="$(submit '' \
  "$SUITE/slurm/run_knn_observed_cuda.sh")"
KNN_CPU="$(submit '' \
  "$SUITE/slurm/run_knn_sensitivity_cpu4.sh")"
KNN_CUDA="$(submit '' \
  "$SUITE/slurm/run_knn_sensitivity_cuda.sh")"
COMPONENT_CPU="$(submit '' \
  "$SUITE/slurm/run_components_cpu12.sh")"
COMPONENT_CUDA="$(submit '' \
  "$SUITE/slurm/run_components_cuda.sh")"
LONGRUN_CPU="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_longrun_cpu4.sh")"
LONGRUN_CUDA="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_longrun_cuda.sh")"
LONGRUN_FINAL_CPU="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_longrun_final_cpu4.sh")"
LONGRUN_FINAL_CUDA="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_longrun_final_cuda.sh")"
LONGRUN_THREADS="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_longrun_threads_cpu12.sh")"
LONGRUN_PYTHON="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_longrun_python_cpu4.sh")"
TIMING_CPU="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_timing_cpu4.sh")"
TIMING_CUDA="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_timing_cuda.sh")"
TIMING_PYTHON="$(submit "afterok:$LONGRUN_INPUT" \
  "$SUITE/slurm/run_tsne_timing_python_cpu4.sh")"

ALL="afterany:$AFFINITY:$SUPPORT_CPU:$SUPPORT_CUDA:$TRANSFORM_CPU"
ALL="$ALL:$QUALITY_CPU:$QUALITY_CUDA"
ALL="$ALL:$TRANSFORM_CUDA:$LANDMARK_CPU:$LANDMARK_CUDA"
ALL="$ALL:$SCALING:$PCA_CPU:$PCA_CUDA"
ALL="$ALL:$PCA_ACCURACY_CPU:$PCA_ACCURACY_CUDA"
ALL="$ALL:$KNN_OBSERVED_CPU:$KNN_OBSERVED_CUDA:$KNN_CPU"
ALL="$ALL:$KNN_CUDA:$COMPONENT_CPU:$COMPONENT_CUDA"
ALL="$ALL:$LONGRUN_CPU:$LONGRUN_CUDA:$LONGRUN_FINAL_CPU"
ALL="$ALL:$LONGRUN_FINAL_CUDA:$LONGRUN_THREADS:$LONGRUN_PYTHON"
ALL="$ALL:$TIMING_CPU:$TIMING_CUDA:$TIMING_PYTHON"
AGGREGATE="$(submit "$ALL" "$SUITE/slurm/run_aggregate_cpu1.sh")"

cat <<EOF
Submitted fastEmbedR JSS validation suite.
  preflight gate:     passed before submission
  shared precompute:  $PRECOMPUTE
  long-run inputs:    $LONGRUN_INPUT
  affinity:           $AFFINITY
  support CPU/CUDA:   $SUPPORT_CPU / $SUPPORT_CUDA
  quality CPU/CUDA:   $QUALITY_CPU / $QUALITY_CUDA
  transform CPU/CUDA: $TRANSFORM_CPU / $TRANSFORM_CUDA
  landmark CPU/CUDA:  $LANDMARK_CPU / $LANDMARK_CUDA
  CPU scaling:        $SCALING
  PCA CPU/CUDA:       $PCA_CPU / $PCA_CUDA
  PCA accuracy:       $PCA_ACCURACY_CPU / $PCA_ACCURACY_CUDA
  observed KNN recall: $KNN_OBSERVED_CPU / $KNN_OBSERVED_CUDA
  KNN CPU/CUDA:       $KNN_CPU / $KNN_CUDA
  components CPU/GPU: $COMPONENT_CPU / $COMPONENT_CUDA
  long-run CPU/CUDA:  $LONGRUN_CPU / $LONGRUN_CUDA
  long-run final:     $LONGRUN_FINAL_CPU / $LONGRUN_FINAL_CUDA
  long-run threads:   $LONGRUN_THREADS
  Python reference:   $LONGRUN_PYTHON
  timing CPU/CUDA:    $TIMING_CPU / $TIMING_CUDA
  timing Python:      $TIMING_PYTHON
  aggregate:          $AGGREGATE
EOF
