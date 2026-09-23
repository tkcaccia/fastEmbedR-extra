#!/usr/bin/env bash

# Shared runner used by the dataset-specific Slurm launchers. This file has no
# SBATCH header: submit one of jobs_by_dataset/run_*_{cpu1,cpu4,cuda}.sh.

set -euo pipefail

BENCHMARK_DATASET="${BENCHMARK_DATASET:?Set BENCHMARK_DATASET in the dataset launcher.}"
BENCHMARK_BACKEND_GROUP="${BENCHMARK_BACKEND_GROUP:?Set BENCHMARK_BACKEND_GROUP to cpu or cuda.}"
BENCHMARK_THREADS="${BENCHMARK_THREADS:?Set BENCHMARK_THREADS in the dataset launcher.}"
BENCHMARK_SUITE="${BENCHMARK_SUITE:-standard}"

case "${BENCHMARK_BACKEND_GROUP}" in
  cpu|cuda) ;;
  *) echo "BENCHMARK_BACKEND_GROUP must be cpu or cuda." >&2; exit 2 ;;
esac
case "${BENCHMARK_THREADS}" in
  1|4) ;;
  *) echo "BENCHMARK_THREADS must be 1 or 4." >&2; exit 2 ;;
esac
if [[ "${BENCHMARK_BACKEND_GROUP}" == "cuda" && "${BENCHMARK_THREADS}" != "1" ]]; then
  echo "CUDA jobs use BENCHMARK_THREADS=1; GPU execution is not labelled as multi-CPU." >&2
  exit 2
fi
case "${BENCHMARK_SUITE}" in
  standard|landmark|kodama) ;;
  *) echo "BENCHMARK_SUITE must be standard, landmark, or kodama." >&2; exit 2 ;;
esac

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
DATA_ROOT="${DATA_ROOT:-${BASE_DIR}/Data}"
IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
SEEDS="${SEEDS:-4,17,42}"
K="${K:-30}"
PERPLEXITY="${PERPLEXITY:-30}"
TIMEOUT="${TIMEOUT:-10800}"
QUALITY_MAX_DISTANCE_OPS="${QUALITY_MAX_DISTANCE_OPS:-200000000}"
LANDMARK_FRACTION="${LANDMARK_FRACTION:-0.5}"
REFERENCE_VALIDATIONS="${REFERENCE_VALIDATIONS:-TRUE}"
BENCHMARK_METHODS="${BENCHMARK_METHODS:-}"
KODAMA_M="${KODAMA_M:-100}"
KODAMA_TCYCLE="${KODAMA_TCYCLE:-20}"
KODAMA_NCOMP="${KODAMA_NCOMP:-50}"
KODAMA_LANDMARKS="${KODAMA_LANDMARKS:-10000000}"
KODAMA_GRAPH_NEIGHBORS="${KODAMA_GRAPH_NEIGHBORS:-100}"
KODAMA_N_EPOCHS="${KODAMA_N_EPOCHS:-200}"
KODAMA_N_ITER="${KODAMA_N_ITER:-500}"
FORCE="${FORCE:-FALSE}"
DRY_RUN="${DRY_RUN:-FALSE}"

STANDARD_CPU_METHODS="fastEmbedR_pca_cpu,irlba_pca,fastEmbedR_opentsne_cpu_full,fastEmbedR_opentsne_cpu_knn,Rtsne_full,Rtsne_neighbors,KlugerLab_FItSNE,fastEmbedR_umap_cpu_fuzzy_full,fastEmbedR_umap_cpu_fuzzy_knn,fastEmbedR_umap_cpu_binary_full,fastEmbedR_umap_cpu_binary_knn,uwot_default,uwot_fast_sgd,uwot_knn,umap_package,umap_package_knn"
STANDARD_CUDA_METHODS="fastEmbedR_pca_cuda,fastEmbedR_opentsne_cuda_full,fastEmbedR_opentsne_cuda_knn,fastEmbedR_umap_cuda_fuzzy_full,fastEmbedR_umap_cuda_fuzzy_knn,fastEmbedR_umap_cuda_binary_full,fastEmbedR_umap_cuda_binary_knn,rapids_cuml_tsne_full,rapids_cuml_umap_full"
KODAMA_CPU_METHODS="KODAMA_plslda_opentsne_cpu,KODAMA_knn_opentsne_cpu,KODAMA_plslda_umap_cpu,KODAMA_knn_umap_cpu"
KODAMA_CUDA_METHODS="KODAMA_plslda_opentsne_cuda,KODAMA_knn_opentsne_cuda,KODAMA_plslda_umap_cuda,KODAMA_knn_umap_cuda"
if [[ -z "${BENCHMARK_METHODS}" ]]; then
  if [[ "${BENCHMARK_SUITE}" == "kodama" && "${BENCHMARK_BACKEND_GROUP}" == "cpu" ]]; then
    BENCHMARK_METHODS="${KODAMA_CPU_METHODS}"
  elif [[ "${BENCHMARK_SUITE}" == "kodama" ]]; then
    BENCHMARK_METHODS="${KODAMA_CUDA_METHODS}"
  elif [[ "${BENCHMARK_BACKEND_GROUP}" == "cpu" ]]; then
    BENCHMARK_METHODS="${STANDARD_CPU_METHODS}"
  else
    BENCHMARK_METHODS="${STANDARD_CUDA_METHODS}"
  fi
fi

safe_dataset="$(printf '%s' "${BENCHMARK_DATASET}" | tr -c 'A-Za-z0-9_.-' '_')"
if [[ "${BENCHMARK_BACKEND_GROUP}" == "cuda" ]]; then
  profile="cuda"
else
  profile="cpu${BENCHMARK_THREADS}"
fi
run_stamp="${RUN_STAMP:-$(date +%Y%m%d_%H%M%S)}"
job_suffix="${SLURM_JOB_ID:-manual}"
RESULTS_ROOT="${RESULTS_ROOT:-${BASE_DIR}/fastEmbedR-results}"
LAYOUT_ROOT="${LAYOUT_ROOT:-${BASE_DIR}/fastEmbedR-rlayout}"
INPUT_ROOT="${INPUT_ROOT:-${BASE_DIR}/fastEmbedR-input}"
run_folder="${run_stamp}_${job_suffix}"
OUT_DIR="${OUT_DIR:-${RESULTS_ROOT}/${safe_dataset}/${BENCHMARK_SUITE}/${profile}/${run_folder}}"
LAYOUT_DIR="${LAYOUT_DIR:-${LAYOUT_ROOT}/${safe_dataset}/${BENCHMARK_SUITE}/${profile}/${run_folder}}"
CACHE_DIR="${CACHE_DIR:-${INPUT_ROOT}/precomputed}"

runner_path="${BASH_SOURCE[0]:-$0}"
if command -v readlink >/dev/null 2>&1; then
  runner_path="$(readlink -f "${runner_path}" 2>/dev/null || printf '%s\n' "${runner_path}")"
fi
runner_dir="$(cd "$(dirname "${runner_path}")" && pwd)"

resolve_file() {
  local name="$1"
  local candidate
  for candidate in \
    "${runner_dir}/${name}" \
    "${SCRIPT_DIR:-}/${name}" \
    "${BASE_DIR}/${name}" \
    "${BASE_DIR}/benchmark_scripts/${name}"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  echo "Cannot find ${name}. Copy the reviewer benchmark files together." >&2
  return 1
}

BENCH_R="$(resolve_file benchmark_reviewer_validation.R)"
METRICS_R="$(resolve_file publication_metrics.R)"
MONITOR_SH="$(resolve_file benchmark_worker_monitor.sh)"
REFERENCE_PY="$(resolve_file reference_opentsne_affinity.py)"

for required in "${BENCH_R}" "${METRICS_R}" "${MONITOR_SH}" "${REFERENCE_PY}" "${IMAGE}"; do
  [[ -f "${required}" ]] || { echo "Missing required file: ${required}" >&2; exit 1; }
done

CONTAINER="$(command -v apptainer || command -v singularity || true)"
[[ -n "${CONTAINER}" ]] || { echo "apptainer/singularity was not found" >&2; exit 1; }

mkdir -p \
  "${BASE_DIR}/benchmark_logs" "${RESULTS_ROOT}" "${LAYOUT_ROOT}" "${INPUT_ROOT}" \
  "${OUT_DIR}" "${LAYOUT_DIR}" "${CACHE_DIR}"

export OMP_NUM_THREADS="${BENCHMARK_THREADS}"
export OPENBLAS_NUM_THREADS="${BENCHMARK_THREADS}"
export MKL_NUM_THREADS="${BENCHMARK_THREADS}"
export VECLIB_MAXIMUM_THREADS="${BENCHMARK_THREADS}"
export RCPP_PARALLEL_NUM_THREADS="${BENCHMARK_THREADS}"
export APPTAINERENV_OMP_NUM_THREADS="${BENCHMARK_THREADS}"
export APPTAINERENV_OPENBLAS_NUM_THREADS="${BENCHMARK_THREADS}"
export APPTAINERENV_MKL_NUM_THREADS="${BENCHMARK_THREADS}"
export APPTAINERENV_RCPP_PARALLEL_NUM_THREADS="${BENCHMARK_THREADS}"

container_args=(exec)
if [[ "${BENCHMARK_BACKEND_GROUP}" == "cuda" ]]; then
  container_args+=(--nv)
  export APPTAINERENV_LD_LIBRARY_PATH="/opt/rapids/lib:/opt/faiss/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
fi
container_args+=(--bind "${BASE_DIR}:${BASE_DIR}" --pwd "${BASE_DIR}" "${IMAGE}")

r_args=(
  "${BENCH_R}"
  "--backend-group=${BENCHMARK_BACKEND_GROUP}"
  "--base-dir=${BASE_DIR}"
  "--data-root=${DATA_ROOT}"
  "--out-dir=${OUT_DIR}"
  "--layout-dir=${LAYOUT_DIR}"
  "--input-dir=${INPUT_ROOT}"
  "--cache-dir=${CACHE_DIR}"
  "--datasets=${BENCHMARK_DATASET}"
  "--threads-grid=${BENCHMARK_THREADS}"
  "--seeds=${SEEDS}"
  "--k=${K}"
  "--perplexity=${PERPLEXITY}"
  "--timeout=${TIMEOUT}"
  "--quality-max-distance-ops=${QUALITY_MAX_DISTANCE_OPS}"
  "--landmark-fraction=${LANDMARK_FRACTION}"
  "--reference-validations=${REFERENCE_VALIDATIONS}"
  "--kodama-m=${KODAMA_M}"
  "--kodama-tcycle=${KODAMA_TCYCLE}"
  "--kodama-ncomp=${KODAMA_NCOMP}"
  "--kodama-landmarks=${KODAMA_LANDMARKS}"
  "--kodama-graph-neighbors=${KODAMA_GRAPH_NEIGHBORS}"
  "--kodama-n-epochs=${KODAMA_N_EPOCHS}"
  "--kodama-n-iter=${KODAMA_N_ITER}"
  "--force=${FORCE}"
)
if [[ -n "${BENCHMARK_METHODS}" ]]; then
  r_args+=("--methods=${BENCHMARK_METHODS}")
fi

echo "fastEmbedR reviewer dataset job"
echo "  dataset: ${BENCHMARK_DATASET}"
echo "  suite:   ${BENCHMARK_SUITE}"
echo "  backend: ${BENCHMARK_BACKEND_GROUP}"
echo "  threads: ${BENCHMARK_THREADS}"
echo "  data:    ${DATA_ROOT}"
echo "  output:  ${OUT_DIR}"
echo "  layouts: ${LAYOUT_DIR}"
echo "  inputs:  ${INPUT_ROOT}"
echo "  cache:   ${CACHE_DIR}"
echo "  image:   ${IMAGE}"
echo "  landmark fraction: ${LANDMARK_FRACTION}"
echo "  reference validations: ${REFERENCE_VALIDATIONS}"
echo "  KODAMA:  M=${KODAMA_M} Tcycle=${KODAMA_TCYCLE} ncomp=${KODAMA_NCOMP} landmarks=${KODAMA_LANDMARKS}"
echo "  methods: ${BENCHMARK_METHODS}"

case "$(printf '%s' "${DRY_RUN}" | tr '[:upper:]' '[:lower:]')" in
true|1|yes)
  printf 'DRY RUN:'
  printf ' %q' "${CONTAINER}" "${container_args[@]}" /opt/conda/bin/Rscript "${r_args[@]}"
  printf '\n'
  exit 0
  ;;
esac

"${CONTAINER}" "${container_args[@]}" /opt/conda/bin/Rscript "${r_args[@]}"

echo "DONE: ${OUT_DIR}"
