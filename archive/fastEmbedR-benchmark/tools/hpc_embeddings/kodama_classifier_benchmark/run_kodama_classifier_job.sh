#!/usr/bin/env bash

# Execute one dataset/classifier/backend/landmark KODAMA job in the validated
# fastEmbedR Apptainer image. Generated Slurm launchers set the required values.

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
DATA_ROOT="${DATA_ROOT:-${BASE_DIR}/Data}"
IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
BENCHMARK_DATASET="${BENCHMARK_DATASET:?Set BENCHMARK_DATASET.}"
KODAMA_CLASSIFIER="${KODAMA_CLASSIFIER:?Set KODAMA_CLASSIFIER to pls_lda or knn.}"
KODAMA_BACKEND="${KODAMA_BACKEND:?Set KODAMA_BACKEND to cpu or cuda.}"
KODAMA_THREADS="${KODAMA_THREADS:?Set KODAMA_THREADS.}"
KODAMA_LANDMARK_MODE="${KODAMA_LANDMARK_MODE:-default}"
KODAMA_LANDMARK_FRACTION="${KODAMA_LANDMARK_FRACTION:-NA}"
KODAMA_DEFAULT_LANDMARKS="${KODAMA_DEFAULT_LANDMARKS:-10000000}"
KODAMA_LARGE_THRESHOLD="${KODAMA_LARGE_THRESHOLD:-10000}"
KODAMA_M="${KODAMA_M:-100}"
KODAMA_TCYCLE="${KODAMA_TCYCLE:-100}"
KODAMA_NCOMP="${KODAMA_NCOMP:-50}"
KODAMA_K="${KODAMA_K:-30}"
KODAMA_PERPLEXITY="${KODAMA_PERPLEXITY:-30}"
KODAMA_GRAPH_NEIGHBORS="${KODAMA_GRAPH_NEIGHBORS:-100}"
KODAMA_N_EPOCHS="${KODAMA_N_EPOCHS:-200}"
KODAMA_N_ITER="${KODAMA_N_ITER:-500}"
SEEDS="${SEEDS:-4,17,42}"
TIMEOUT="${TIMEOUT:-172800}"
FORCE="${FORCE:-FALSE}"
QUALITY_SAMPLE_N="${QUALITY_SAMPLE_N:-5000}"
PLOT_MAX_POINTS="${PLOT_MAX_POINTS:-250000}"

case "${KODAMA_CLASSIFIER}" in
  pls_lda) R_SCRIPT="benchmark_kodama_plslda.R" ;;
  knn) R_SCRIPT="benchmark_kodama_knn.R" ;;
  *) echo "KODAMA_CLASSIFIER must be pls_lda or knn." >&2; exit 2 ;;
esac
case "${KODAMA_BACKEND}" in
  cpu|cuda) ;;
  *) echo "KODAMA_BACKEND must be cpu or cuda." >&2; exit 2 ;;
esac
case "${KODAMA_LANDMARK_MODE}" in
  default|fraction) ;;
  *) echo "KODAMA_LANDMARK_MODE must be default or fraction." >&2; exit 2 ;;
esac

SCRIPT_ROOT="${BASE_DIR}/benchmark_scripts/kodama_classifier_benchmark"
BENCH_R="${SCRIPT_ROOT}/${R_SCRIPT}"
COMMON_R="${SCRIPT_ROOT}/kodama_benchmark_common.R"
MONITOR_SH="${BASE_DIR}/benchmark_scripts/benchmark_worker_monitor.sh"
for required in "${IMAGE}" "${BENCH_R}" "${COMMON_R}" "${MONITOR_SH}"; do
  [[ -f "${required}" ]] || {
    echo "Missing required file: ${required}" >&2
    exit 1
  }
done

CONTAINER="$(command -v apptainer || command -v singularity || true)"
[[ -n "${CONTAINER}" ]] || {
  echo "apptainer/singularity was not found." >&2
  exit 1
}

safe_dataset="$(printf '%s' "${BENCHMARK_DATASET}" | tr -c 'A-Za-z0-9_.-' '_')"
variant_tag="default"
if [[ "${KODAMA_LANDMARK_MODE}" == "fraction" ]]; then
  variant_tag="$(
    awk -v value="${KODAMA_LANDMARK_FRACTION}" \
      'BEGIN { printf "landmark%02d", int(value * 100 + 0.5) }'
  )"
fi
profile="cpu${KODAMA_THREADS}"
if [[ "${KODAMA_BACKEND}" == "cuda" ]]; then
  profile="cuda"
fi
GRAPH_ROOT="${KODAMA_GRAPH_ROOT:-${BASE_DIR}/fastEmbedR-input/kodama_graphs}"
KODAMA_GRAPH_FILE="${KODAMA_GRAPH_FILE:-${GRAPH_ROOT}/${safe_dataset}/${profile}/kodama_graph_k${KODAMA_GRAPH_NEIGHBORS}_seed4.rds}"
[[ -f "${KODAMA_GRAPH_FILE}" ]] || {
  echo "Shared KODAMA graph is missing: ${KODAMA_GRAPH_FILE}" >&2
  echo "Submit the matching graph preparation job before this analysis." >&2
  exit 1
}
run_stamp="${RUN_STAMP:-$(date +%Y%m%d_%H%M%S)}"
job_suffix="${SLURM_ARRAY_JOB_ID:-${SLURM_JOB_ID:-manual}}_${SLURM_ARRAY_TASK_ID:-0}"
run_folder="${run_stamp}_${job_suffix}"
RESULTS_ROOT="${RESULTS_ROOT:-${BASE_DIR}/fastEmbedR-results}"
LAYOUT_ROOT="${LAYOUT_ROOT:-${BASE_DIR}/fastEmbedR-rlayout}"
OUT_DIR="${OUT_DIR:-${RESULTS_ROOT}/${safe_dataset}/kodama_${KODAMA_CLASSIFIER}/${profile}/${variant_tag}/${run_folder}}"
LAYOUT_DIR="${LAYOUT_DIR:-${LAYOUT_ROOT}/${safe_dataset}/kodama_${KODAMA_CLASSIFIER}/${profile}/${variant_tag}/${run_folder}}"

mkdir -p \
  "${BASE_DIR}/benchmark_logs" "${OUT_DIR}" "${LAYOUT_DIR}" \
  "${RESULTS_ROOT}" "${LAYOUT_ROOT}"

export OMP_NUM_THREADS="${KODAMA_THREADS}"
export OPENBLAS_NUM_THREADS="${KODAMA_THREADS}"
export MKL_NUM_THREADS="${KODAMA_THREADS}"
export VECLIB_MAXIMUM_THREADS="${KODAMA_THREADS}"
export RCPP_PARALLEL_NUM_THREADS="${KODAMA_THREADS}"
export APPTAINERENV_OMP_NUM_THREADS="${KODAMA_THREADS}"
export APPTAINERENV_OPENBLAS_NUM_THREADS="${KODAMA_THREADS}"
export APPTAINERENV_MKL_NUM_THREADS="${KODAMA_THREADS}"
export APPTAINERENV_RCPP_PARALLEL_NUM_THREADS="${KODAMA_THREADS}"

container_args=(exec)
if [[ "${KODAMA_BACKEND}" == "cuda" ]]; then
  container_args+=(--nv)
  export APPTAINERENV_LD_LIBRARY_PATH="/opt/rapids/lib:/opt/faiss/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
  nvidia-smi -L
fi
container_args+=(--bind "${BASE_DIR}:${BASE_DIR}" --pwd "${BASE_DIR}" "${IMAGE}")

r_args=(
  "${BENCH_R}"
  "--dataset=${BENCHMARK_DATASET}"
  "--backend=${KODAMA_BACKEND}"
  "--n-cores=${KODAMA_THREADS}"
  "--data-root=${DATA_ROOT}"
  "--out-dir=${OUT_DIR}"
  "--layout-dir=${LAYOUT_DIR}"
  "--monitor-script=${MONITOR_SH}"
  "--seeds=${SEEDS}"
  "--timeout=${TIMEOUT}"
  "--M=${KODAMA_M}"
  "--Tcycle=${KODAMA_TCYCLE}"
  "--ncomp=${KODAMA_NCOMP}"
  "--k=${KODAMA_K}"
  "--perplexity=${KODAMA_PERPLEXITY}"
  "--graph-neighbors=${KODAMA_GRAPH_NEIGHBORS}"
  "--graph-file=${KODAMA_GRAPH_FILE}"
  "--n-epochs=${KODAMA_N_EPOCHS}"
  "--n-iter=${KODAMA_N_ITER}"
  "--quality-sample-n=${QUALITY_SAMPLE_N}"
  "--plot-max-points=${PLOT_MAX_POINTS}"
  "--landmark-mode=${KODAMA_LANDMARK_MODE}"
  "--landmark-fraction=${KODAMA_LANDMARK_FRACTION}"
  "--default-landmarks=${KODAMA_DEFAULT_LANDMARKS}"
  "--large-threshold=${KODAMA_LARGE_THRESHOLD}"
  "--force=${FORCE}"
)

echo "KODAMA classifier benchmark"
echo "  dataset:           ${BENCHMARK_DATASET}"
echo "  classifier:        ${KODAMA_CLASSIFIER}"
echo "  backend:           ${KODAMA_BACKEND}"
echo "  CPU cores:         ${KODAMA_THREADS}"
echo "  landmark mode:     ${KODAMA_LANDMARK_MODE}"
echo "  landmark fraction: ${KODAMA_LANDMARK_FRACTION}"
echo "  M/Tcycle:          ${KODAMA_M}/${KODAMA_TCYCLE}"
echo "  seeds:             ${SEEDS}"
echo "  shared graph:      ${KODAMA_GRAPH_FILE}"
echo "  results:           ${OUT_DIR}"
echo "  layouts:           ${LAYOUT_DIR}"
echo "  image:             ${IMAGE}"

if [[ "${DRY_RUN:-FALSE}" =~ ^([Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss])$ ]]; then
  printf 'DRY RUN:'
  printf ' %q' "${CONTAINER}" "${container_args[@]}" /opt/conda/bin/Rscript "${r_args[@]}"
  printf '\n'
  exit 0
fi

"${CONTAINER}" "${container_args[@]}" /opt/conda/bin/Rscript "${r_args[@]}"
echo "DONE: ${OUT_DIR}"
