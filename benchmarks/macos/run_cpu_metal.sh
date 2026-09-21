#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

PACKAGE_ROOT="${FASTEMBEDR_PACKAGE_ROOT:-/Users/stefano/Documents/umap}"
DATA_ROOT="${FASTEMBEDR_DATA_ROOT:-/Users/stefano/Documents/fastEmbedR/Data}"
RESULTS_ROOT="${FASTEMBEDR_RESULTS_ROOT:-${repo_root}/results/runs/macos}"
RUN_ID="${FASTEMBEDR_RUN_ID:-macos_$(date +%Y%m%d_%H%M%S)}"
OUT_DIR="${OUT_DIR:-${RESULTS_ROOT}/${RUN_ID}}"
INPUT_ROOT="${INPUT_ROOT:-${repo_root}/fastEmbedR-input/macos}"
CACHE_DIR="${CACHE_DIR:-${INPUT_ROOT}/precomputed}"
R_LIBRARY="${R_LIBRARY:-${OUT_DIR}/Rlib}"
ALLOW_DIRTY="${ALLOW_DIRTY:-FALSE}"

DATASETS="${DATASETS:-COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,MetRef,mass41,TabulaMuris,Macosko2015_retina,imagenet}"
METHODS="${METHODS:-fastEmbedR_pca_cpu,fastEmbedR_tsne_cpu_full,fastEmbedR_tsne_cpu_knn,fastEmbedR_umap_cpu_fuzzy_full,fastEmbedR_umap_cpu_fuzzy_knn,fastEmbedR_umap_cpu_binary_full,fastEmbedR_umap_cpu_binary_knn,fastEmbedR_pca_metal,fastEmbedR_tsne_metal_full,fastEmbedR_tsne_metal_knn,fastEmbedR_umap_metal_fuzzy_full,fastEmbedR_umap_metal_fuzzy_knn,fastEmbedR_umap_metal_binary_full,fastEmbedR_umap_metal_binary_knn}"
THREADS_GRID="${THREADS_GRID:-1,4}"
SEEDS="${SEEDS:-4,17,42}"
K="${K:-30}"
PERPLEXITY="${PERPLEXITY:-30}"
TIMEOUT="${TIMEOUT:-43200}"
QUALITY_MAX_DISTANCE_OPS="${QUALITY_MAX_DISTANCE_OPS:-200000000}"
LOCAL_CPU_MAX_N="${LOCAL_CPU_MAX_N:-100000}"
LOCAL_CPU_EXCEPTIONS="${LOCAL_CPU_EXCEPTIONS:-TabulaMuris}"
FORCE="${FORCE:-FALSE}"

BENCH_R="${repo_root}/benchmarks/shared/benchmark_reviewer_validation.R"
for required in "${BENCH_R}" \
  "${repo_root}/benchmarks/shared/publication_metrics.R" \
  "${repo_root}/benchmarks/shared/benchmark_worker_monitor.sh" \
  "${repo_root}/benchmarks/shared/reference_opentsne_affinity.py"; do
  [[ -f "${required}" ]] || {
    echo "Missing required file: ${required}" >&2
    exit 1
  }
done

[[ -d "${PACKAGE_ROOT}" ]] || {
  echo "Missing fastEmbedR source: ${PACKAGE_ROOT}" >&2
  exit 1
}
[[ -d "${DATA_ROOT}" ]] || {
  echo "Missing dataset root: ${DATA_ROOT}" >&2
  exit 1
}

package_commit="$(git -C "${PACKAGE_ROOT}" rev-parse HEAD)"
package_status="$(git -C "${PACKAGE_ROOT}" status --short)"
if [[ -n "${package_status}" && "${ALLOW_DIRTY}" != "TRUE" ]]; then
  echo "fastEmbedR source is dirty; set ALLOW_DIRTY=TRUE only for development." >&2
  git -C "${PACKAGE_ROOT}" status --short >&2
  exit 1
fi

mkdir -p "${OUT_DIR}" "${INPUT_ROOT}" "${CACHE_DIR}" "${R_LIBRARY}"

{
  echo "fastEmbedR_commit=${package_commit}"
  echo "fastEmbedR_dirty=$([[ -n "${package_status}" ]] && echo yes || echo no)"
  echo "benchmark_commit=$(git -C "${repo_root}" rev-parse HEAD)"
  echo "benchmark_dirty=$([[ -n "$(git -C "${repo_root}" status --short)" ]] && echo yes || echo no)"
} > "${OUT_DIR}/source_identity.txt"

R CMD INSTALL --preclean --library="${R_LIBRARY}" "${PACKAGE_ROOT}" \
  > "${OUT_DIR}/install.log" 2>&1
export R_LIBS_USER="${R_LIBRARY}${R_LIBS_USER:+:${R_LIBS_USER}}"

Rscript -e '
  library(fastEmbedR)
  capabilities <- fastEmbedR_capabilities()
  print(capabilities)
  metal <- capabilities[
    capabilities$backend == "metal", c("knn_available", "embedding_available")
  ]
  stopifnot(nrow(metal) == 1L, all(unlist(metal), na.rm = FALSE))
' > "${OUT_DIR}/capabilities.log" 2>&1

export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
export VECLIB_MAXIMUM_THREADS=4
export RCPP_PARALLEL_NUM_THREADS=4

Rscript "${BENCH_R}" \
  --backend-group=local \
  --base-dir="${repo_root}" \
  --data-root="${DATA_ROOT}" \
  --out-dir="${OUT_DIR}" \
  --input-dir="${INPUT_ROOT}" \
  --cache-dir="${CACHE_DIR}" \
  --datasets="${DATASETS}" \
  --methods="${METHODS}" \
  --threads-grid="${THREADS_GRID}" \
  --seeds="${SEEDS}" \
  --k="${K}" \
  --perplexity="${PERPLEXITY}" \
  --timeout="${TIMEOUT}" \
  --quality-max-distance-ops="${QUALITY_MAX_DISTANCE_OPS}" \
  --local-cpu-max-n="${LOCAL_CPU_MAX_N}" \
  --local-cpu-exceptions="${LOCAL_CPU_EXCEPTIONS}" \
  --force="${FORCE}"

echo "macOS CPU/Metal benchmark complete: ${OUT_DIR}"
