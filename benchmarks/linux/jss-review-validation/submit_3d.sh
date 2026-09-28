#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
: "${INPUT_ROOT:?Set INPUT_ROOT to a completed campaign input directory.}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation/three_d/$(date -u +%Y%m%dT%H%M%SZ)}"
[[ -f "$IMAGE" ]] || { echo "Missing image: $IMAGE" >&2; exit 1; }
FASTEMBEDR_SUITE_MANIFEST_SHA256="$(
  sha256sum "$SUITE/FILES.sha256" | cut -d ' ' -f 1
)"
export SUITE FASTEMBEDR_SUITE_MANIFEST_SHA256
source "$SUITE/common/campaign_submit.sh"
campaign_verify_suite_revision
[[ -f "$INPUT_ROOT/MNIST/matched_inputs.rds" ]] || {
  echo "Missing shared R inputs: $INPUT_ROOT" >&2
  exit 1
}
[[ -f "$INPUT_ROOT/MNIST/workflow_comparators/data_float32.bin" ]] || {
  echo "Missing shared Python inputs: $INPUT_ROOT" >&2
  exit 1
}
OUTPUT_ROOT="$BASE_DIR/fastEmbedR-results/jss_validation" \
  bash "$SUITE/verify_preflight.sh"

source "$SUITE/common/container_runtime.sh"
CONTAINER="$(command -v apptainer || command -v singularity)"
"$CONTAINER" exec --cleanenv \
  --bind "$BASE_DIR:$BASE_DIR" --pwd "$BASE_DIR" \
  "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
  "$IMAGE" "$FASTEMBEDR_RSCRIPT" -e '
    stopifnot(exists(
      "tsne_fft_3d_force_diagnostic_cpp",
      envir = asNamespace("fastEmbedR"), inherits = FALSE
    ))
  '

mkdir -p "$OUTPUT_ROOT" "$BASE_DIR/benchmark_logs"
export BASE_DIR SUITE IMAGE INPUT_ROOT OUTPUT_ROOT N_COMPONENTS=3
printf 'role\tjob_id\n' > "$OUTPUT_ROOT/jobs_3d.tsv"
CPU_R_JOB="$(sbatch --parsable \
  "$SUITE/slurm/run_comparators_r_cpu4_3d.sh")"
CPU_PY_JOB="$(sbatch --parsable \
  "$SUITE/slurm/run_comparators_python_cpu4_3d.sh")"
GPU_R_JOB="$(sbatch --parsable \
  "$SUITE/slurm/run_comparators_r_cuda_3d.sh")"
export CPU_R_JOB CPU_PY_JOB
CONTROLLER_JOB="$(sbatch --parsable \
  --dependency="afterany:$GPU_R_JOB" \
  "$SUITE/slurm/run_3d_gpu_controller_cpu1.sh")"
printf 'r_cpu\t%s\npython_cpu\t%s\nr_cuda\t%s\ncontroller\t%s\n' \
  "$CPU_R_JOB" "$CPU_PY_JOB" "$GPU_R_JOB" "$CONTROLLER_JOB" \
  >> "$OUTPUT_ROOT/jobs_3d.tsv"
{
  echo "image_sha256=$(sha256sum "$IMAGE" | cut -d ' ' -f 1)"
  echo "input_root=$INPUT_ROOT"
  echo "output_root=$OUTPUT_ROOT"
  echo "n_components=3"
  echo "suite_manifest_sha256=$FASTEMBEDR_SUITE_MANIFEST_SHA256"
} > "$OUTPUT_ROOT/manifest_3d.txt"
cat "$OUTPUT_ROOT/jobs_3d.tsv"
echo "Final audit will be scheduled after the GPU stages."
