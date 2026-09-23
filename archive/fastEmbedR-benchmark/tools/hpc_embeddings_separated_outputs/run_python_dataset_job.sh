#!/usr/bin/env bash

# Run Python UMAP/t-SNE references for one dataset and execution profile.
# CPU jobs exercise openTSNE and umap-learn through both reticulate and a
# native Python subprocess. CUDA jobs exercise RAPIDS cuML the same two ways.

set -euo pipefail

: "${BENCHMARK_DATASET:?Set BENCHMARK_DATASET in the dataset launcher.}"
: "${BENCHMARK_BACKEND_GROUP:?Set BENCHMARK_BACKEND_GROUP to cpu or cuda.}"
: "${BENCHMARK_THREADS:?Set BENCHMARK_THREADS in the dataset launcher.}"

case "${BENCHMARK_BACKEND_GROUP}" in
  cpu|cuda) ;;
  *) echo "BENCHMARK_BACKEND_GROUP must be cpu or cuda." >&2; exit 2 ;;
esac
case "${BENCHMARK_THREADS}" in
  1|4) ;;
  *) echo "BENCHMARK_THREADS must be 1 or 4." >&2; exit 2 ;;
esac
if [[ "${BENCHMARK_BACKEND_GROUP}" == "cuda" && "${BENCHMARK_THREADS}" != "1" ]]; then
  echo "CUDA jobs use BENCHMARK_THREADS=1." >&2
  exit 2
fi

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
DATA_ROOT="${DATA_ROOT:-${BASE_DIR}/Data}"
IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
RESULTS_ROOT="${RESULTS_ROOT:-${BASE_DIR}/fastEmbedR-results}"
LAYOUT_ROOT="${LAYOUT_ROOT:-${BASE_DIR}/fastEmbedR-rlayout}"
SEEDS="${SEEDS:-4,17,42}"
K="${K:-30}"
PERPLEXITY="${PERPLEXITY:-30}"
TIMEOUT="${TIMEOUT:-10800}"
FORCE="${FORCE:-FALSE}"

if [[ -z "${BENCHMARK_METHODS:-}" ]]; then
  if [[ "${BENCHMARK_BACKEND_GROUP}" == "cpu" ]]; then
    BENCHMARK_METHODS="python_opentsne_fft,python_opentsne_fft_direct,python_umap_learn,python_umap_learn_direct"
  else
    BENCHMARK_METHODS="rapids_cuml_tsne_full,rapids_cuml_tsne_full_direct,rapids_cuml_umap_full,rapids_cuml_umap_full_direct"
  fi
fi

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
    "${BASE_DIR}/fastEmbedR_benchmark_jobs/shared/${name}" \
    "${BASE_DIR}/${name}" \
    "${BASE_DIR}/benchmark_scripts/${name}"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  echo "Cannot find ${name}." >&2
  return 1
}

BENCH_R="$(resolve_file benchmark_embeddings_float32_publication.R)"
PY_HELPER="$(resolve_file benchmark_python_direct.py)"
[[ -f "${IMAGE}" ]] || { echo "Missing image: ${IMAGE}" >&2; exit 1; }
[[ -f "${PY_HELPER}" ]] || { echo "Missing Python helper: ${PY_HELPER}" >&2; exit 1; }

CONTAINER="$(command -v apptainer || command -v singularity || true)"
[[ -n "${CONTAINER}" ]] || { echo "apptainer/singularity was not found." >&2; exit 1; }

safe_dataset="$(printf '%s' "${BENCHMARK_DATASET}" | tr -c 'A-Za-z0-9_.-' '_')"
if [[ "${BENCHMARK_BACKEND_GROUP}" == "cuda" ]]; then
  profile="cuda"
else
  profile="cpu${BENCHMARK_THREADS}"
fi
run_stamp="${RUN_STAMP:-$(date +%Y%m%d_%H%M%S)}"
job_suffix="${SLURM_JOB_ID:-manual}"
run_folder="${run_stamp}_${job_suffix}"

export OMP_NUM_THREADS="${BENCHMARK_THREADS}"
export OPENBLAS_NUM_THREADS="${BENCHMARK_THREADS}"
export MKL_NUM_THREADS="${BENCHMARK_THREADS}"
export NUMBA_NUM_THREADS="${BENCHMARK_THREADS}"
export APPTAINERENV_OMP_NUM_THREADS="${BENCHMARK_THREADS}"
export APPTAINERENV_OPENBLAS_NUM_THREADS="${BENCHMARK_THREADS}"
export APPTAINERENV_MKL_NUM_THREADS="${BENCHMARK_THREADS}"
export APPTAINERENV_NUMBA_NUM_THREADS="${BENCHMARK_THREADS}"

container_args=(exec)
if [[ "${BENCHMARK_BACKEND_GROUP}" == "cuda" ]]; then
  container_args+=(--nv)
  export APPTAINERENV_LD_LIBRARY_PATH="/opt/rapids/lib:/opt/faiss/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
fi
container_args+=(--bind "${BASE_DIR}:${BASE_DIR}" --pwd "${BASE_DIR}" "${IMAGE}")

mkdir -p "${BASE_DIR}/benchmark_logs" "${RESULTS_ROOT}" "${LAYOUT_ROOT}"
overall_status=0
IFS=',' read -r -a seed_values <<< "${SEEDS}"
for run_seed in "${seed_values[@]}"; do
  seed_out="${RESULTS_ROOT}/${safe_dataset}/python/${profile}/${run_folder}/seed_${run_seed}"
  seed_layout="${LAYOUT_ROOT}/${safe_dataset}/python/${profile}/${run_folder}/seed_${run_seed}"
  mkdir -p "${seed_out}" "${seed_layout}"
  echo "Python embedding benchmark: dataset=${BENCHMARK_DATASET} backend=${BENCHMARK_BACKEND_GROUP} threads=${BENCHMARK_THREADS} seed=${run_seed}"
  if ! "${CONTAINER}" "${container_args[@]}" /opt/conda/bin/Rscript "${BENCH_R}" \
      "--script=${BENCH_R}" \
      "--backend_group=${BENCHMARK_BACKEND_GROUP}" \
      "--base_dir=${BASE_DIR}" \
      "--data_root=${DATA_ROOT}" \
      "--out_dir=${seed_out}" \
      "--datasets=${BENCHMARK_DATASET}" \
      "--methods=${BENCHMARK_METHODS}" \
      "--threads=${BENCHMARK_THREADS}" \
      "--thread_grid=${BENCHMARK_THREADS}" \
      "--timeout=${TIMEOUT}" \
      "--k=${K}" \
      "--perplexity=${PERPLEXITY}" \
      "--seed=${run_seed}" \
      "--force=${FORCE}"; then
    echo "Python benchmark seed ${run_seed} failed; continuing with remaining seeds." >&2
    overall_status=1
  fi
  if [[ -d "${seed_out}/layouts" ]]; then
    cp -R "${seed_out}/layouts/." "${seed_layout}/"
  fi
done

exit "${overall_status}"
