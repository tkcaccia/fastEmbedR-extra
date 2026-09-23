#!/usr/bin/env bash
set -u

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
DATA_ROOT="${DATA_ROOT:-${BASE_DIR}/Data}"
CACHE_ROOT="${CACHE_ROOT:-${BASE_DIR}/fastEmbedR-input/multicore_scaling}"
OUT_ROOT="${OUT_ROOT:-${BASE_DIR}/fastEmbedR-results/multicore_scaling_$(date +%Y%m%d_%H%M%S)}"
SCRIPT_DIR="${SCRIPT_DIR:-${BASE_DIR}/benchmark_scripts/multicore_scaling}"
IMAGE="${IMAGE:-}"
THREAD_GRID="${THREAD_GRID:-1,2,4,8,16}"
DATASETS="${DATASETS:-MetRef,MNIST,simulated_1M_2D}"
STAGES="${STAGES:-knn,pca_initialization,tsne_embedding,umap_graph,umap_initialization,umap_optimization,full_opentsne,full_umap}"
REPEATS="${REPEATS:-5}"
WARMUPS="${WARMUPS:-1}"
SEED="${SEED:-4}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"

mkdir -p "${CACHE_ROOT}" "${OUT_ROOT}/run_level" "${OUT_ROOT}/logs"

run_r() {
  if [[ -n "${IMAGE}" ]]; then
    apptainer exec --cleanenv --bind "${BASE_DIR}:${BASE_DIR}" "${IMAGE}" Rscript "$@"
  else
    Rscript "$@"
  fi
}

run_r "${SCRIPT_DIR}/prepare_multicore_scaling_inputs.R" \
  --data-root="${DATA_ROOT}" --cache-root="${CACHE_ROOT}" \
  --datasets="${DATASETS}" --n.cores=4 --seed="${SEED}" \
  >"${OUT_ROOT}/logs/prepare.log" 2>&1

IFS=',' read -r -a dataset_values <<<"${DATASETS}"
IFS=',' read -r -a stage_values <<<"${STAGES}"
IFS=',' read -r -a thread_values <<<"${THREAD_GRID}"

for dataset in "${dataset_values[@]}"; do
  for stage in "${stage_values[@]}"; do
    for workers in "${thread_values[@]}"; do
      echo "$(date -Is) dataset=${dataset} stage=${stage} workers=${workers} BLAS=1"
      (
        export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
        export VECLIB_MAXIMUM_THREADS=1 RCPP_PARALLEL_NUM_THREADS="${workers}"
        run_r "${SCRIPT_DIR}/benchmark_multicore_scaling_worker.R" \
        --dataset="${dataset}" --stage="${stage}" \
        --data-root="${DATA_ROOT}" --cache-root="${CACHE_ROOT}" \
        --out-dir="${OUT_ROOT}/run_level" --n.cores="${workers}" \
        --blas-threads=1 --repeats="${REPEATS}" --warmups="${WARMUPS}" \
        --seed="${SEED}" --run-id="${RUN_ID}" --scope=primary_scaling \
        >"${OUT_ROOT}/logs/${dataset}_${stage}_w${workers}.log" 2>&1
      ) || true
    done
  done
done

# Oversubscription/BLAS interaction is kept separate from the primary curves.
for stage in pca_initialization full_opentsne full_umap; do
  for workers in 4 8 16; do
    for blas in 1 2 4; do
      echo "$(date -Is) interaction dataset=MNIST stage=${stage} workers=${workers} BLAS=${blas}"
      (
        export OMP_NUM_THREADS="${blas}" OPENBLAS_NUM_THREADS="${blas}"
        export MKL_NUM_THREADS="${blas}" VECLIB_MAXIMUM_THREADS="${blas}"
        export RCPP_PARALLEL_NUM_THREADS="${workers}"
        run_r "${SCRIPT_DIR}/benchmark_multicore_scaling_worker.R" \
        --dataset=MNIST --stage="${stage}" --data-root="${DATA_ROOT}" \
        --cache-root="${CACHE_ROOT}" --out-dir="${OUT_ROOT}/run_level" \
        --n.cores="${workers}" --blas-threads="${blas}" \
        --repeats=3 --warmups=1 --seed="${SEED}" --run-id="${RUN_ID}_blas" \
        --scope=blas_interaction \
        >"${OUT_ROOT}/logs/MNIST_${stage}_w${workers}_b${blas}.log" 2>&1
      ) || true
    done
  done
done

run_r "${SCRIPT_DIR}/summarize_multicore_scaling.R" \
  --input-dir="${OUT_ROOT}/run_level" --out-dir="${OUT_ROOT}/summary"

echo "Completed multicore scaling benchmark: ${OUT_ROOT}"
