#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
DATA_ROOT="${DATA_ROOT:-${BASE_DIR}/Data}"
IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
BENCHMARK_DATASET="${BENCHMARK_DATASET:?Set BENCHMARK_DATASET.}"
KODAMA_BACKEND="${KODAMA_BACKEND:?Set KODAMA_BACKEND to cpu or cuda.}"
KODAMA_THREADS="${KODAMA_THREADS:?Set KODAMA_THREADS.}"
KODAMA_GRAPH_NEIGHBORS="${KODAMA_GRAPH_NEIGHBORS:-100}"
KODAMA_GRAPH_SEED="${KODAMA_GRAPH_SEED:-4}"
FORCE_GRAPH="${FORCE_GRAPH:-FALSE}"

case "${KODAMA_BACKEND}" in
  cpu|cuda) ;;
  *) echo "KODAMA_BACKEND must be cpu or cuda." >&2; exit 2 ;;
esac

safe_dataset="$(printf '%s' "${BENCHMARK_DATASET}" | tr -c 'A-Za-z0-9_.-' '_')"
profile="cpu${KODAMA_THREADS}"
if [[ "${KODAMA_BACKEND}" == "cuda" ]]; then
  profile="cuda"
fi
GRAPH_ROOT="${KODAMA_GRAPH_ROOT:-${BASE_DIR}/fastEmbedR-input/kodama_graphs}"
KODAMA_GRAPH_FILE="${KODAMA_GRAPH_FILE:-${GRAPH_ROOT}/${safe_dataset}/${profile}/kodama_graph_k${KODAMA_GRAPH_NEIGHBORS}_seed${KODAMA_GRAPH_SEED}.rds}"
SCRIPT_ROOT="${BASE_DIR}/benchmark_scripts/kodama_classifier_benchmark"
R_SCRIPT="${SCRIPT_ROOT}/prepare_kodama_graph.R"

for required in "${IMAGE}" "${R_SCRIPT}" \
  "${SCRIPT_ROOT}/kodama_benchmark_common.R"; do
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

mkdir -p "$(dirname "${KODAMA_GRAPH_FILE}")" "${BASE_DIR}/benchmark_logs"
export OMP_NUM_THREADS="${KODAMA_THREADS}"
export OPENBLAS_NUM_THREADS="${KODAMA_THREADS}"
export MKL_NUM_THREADS="${KODAMA_THREADS}"
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

echo "KODAMA shared graph preparation"
echo "  dataset:      ${BENCHMARK_DATASET}"
echo "  backend:      ${KODAMA_BACKEND}"
echo "  CPU cores:    ${KODAMA_THREADS}"
echo "  neighbors:    ${KODAMA_GRAPH_NEIGHBORS}"
echo "  graph file:   ${KODAMA_GRAPH_FILE}"
echo "  force rebuild:${FORCE_GRAPH}"

"${CONTAINER}" "${container_args[@]}" /opt/conda/bin/Rscript \
  "${R_SCRIPT}" \
  "--dataset=${BENCHMARK_DATASET}" \
  "--backend=${KODAMA_BACKEND}" \
  "--n-cores=${KODAMA_THREADS}" \
  "--data-root=${DATA_ROOT}" \
  "--graph-neighbors=${KODAMA_GRAPH_NEIGHBORS}" \
  "--seed=${KODAMA_GRAPH_SEED}" \
  "--graph-file=${KODAMA_GRAPH_FILE}" \
  "--force=${FORCE_GRAPH}"

echo "VALIDATED: ${KODAMA_GRAPH_FILE}"
