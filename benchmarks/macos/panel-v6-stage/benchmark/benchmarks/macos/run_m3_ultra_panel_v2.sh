#!/usr/bin/env bash

# One manuscript dataset per invocation; keep every Mac artifact under Stefano.
set -euo pipefail

stefano=/Users/silvanopiazza/Documents/Stefano
campaign_root="${FASTEMBEDR_MAC_ROOT:-${stefano}/fastEmbedR-mac-20261031}"
dataset="${1:-}"
case "${dataset}" in
  COIL20|USPS|MNIST|FashionMNIST|MetRef|mass41|flow18|imagenet|\
  FlowRepository_FR-FCM-ZYRM_files|TabulaMuris|Macosko2015_retina) ;;
  *) echo "Give one of the eleven manuscript dataset names." >&2; exit 64 ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
benchmark_root="$(cd "${script_dir}/../.." && pwd -P)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This benchmark launcher runs only on the Mac." >&2
  exit 64
fi
campaign_root="$(cd "${campaign_root}" && pwd -P)"
case "${campaign_root}" in
  "${stefano}"/*) ;;
  *) echo "Campaign root must be under ${stefano}." >&2; exit 64 ;;
esac
case "${benchmark_root}" in
  "${stefano}"/*) ;;
  *) echo "Benchmark source must be under ${stefano}." >&2; exit 64 ;;
esac

package_root="${campaign_root}/candidates/mac-benchmark-integration-20261102-v3/source"
archive="${campaign_root}/candidates/mac-benchmark-integration-20261102-v3/fastEmbedR_0.1.tar.gz"
archive_sha=ae37cd4f3638ec59d515456e5c6e0c1bf6d38de8fba05414aab471a0abd76e00
[[ -f "${archive}" && "$(shasum -a 256 "${archive}" | cut -d' ' -f1)" == "${archive_sha}" ]] || {
  echo "Qualified Mac archive identity changed." >&2; exit 1;
}
data_root="${campaign_root}/data"
input_root="${campaign_root}/fastEmbedR-input/m3-ultra-panel-v1"
run_id="${FASTEMBEDR_RUN_ID:-${dataset}_$(date -u +%Y%m%dT%H%M%SZ)}"
[[ "${run_id}" =~ ^[A-Za-z0-9_.-]+$ &&
   "${run_id}" != . && "${run_id}" != .. ]] || {
  echo "Invalid run identifier." >&2; exit 64;
}
out_dir="${campaign_root}/results/m3-ultra-panel-v1/${run_id}"
library="${out_dir}/Rlib"
bench_r="${benchmark_root}/benchmarks/shared/benchmark_reviewer_validation.R"
preflight="${script_dir}/preflight_m3_ultra_panel_v1.py"
methods=fastEmbedR_pca_cpu,fastEmbedR_tsne_cpu_full,fastEmbedR_tsne_cpu_knn,fastEmbedR_umap_cpu_fuzzy_full,fastEmbedR_umap_cpu_fuzzy_knn,fastEmbedR_umap_cpu_binary_full,fastEmbedR_umap_cpu_binary_knn,fastEmbedR_pca_metal,fastEmbedR_tsne_metal_full,fastEmbedR_tsne_metal_knn,fastEmbedR_umap_metal_fuzzy_full,fastEmbedR_umap_metal_fuzzy_knn,fastEmbedR_umap_metal_binary_full,fastEmbedR_umap_metal_binary_knn

[[ -f "${bench_r}" && -f "${preflight}" ]] || {
  echo "Missing benchmark or preflight source." >&2; exit 1;
}
[[ -d "${package_root}" && -d "${data_root}" ]] || {
  echo "Missing package or dataset directory." >&2; exit 1;
}
for source_dir in "${package_root}" "${data_root}"; do
  resolved="$(cd "${source_dir}" && pwd -P)"
  case "${resolved}" in
    "${stefano}"/*) ;;
    *) echo "Source path escapes Stefano: ${source_dir}" >&2; exit 1 ;;
  esac
done
if [[ "${RUN:-FALSE}" != TRUE ]]; then
  echo "DRY RUN: dataset=${dataset}"
  echo "campaign_root=${campaign_root}"
  echo "out_dir=${out_dir}"
  echo "cpu_threads=1,4,8,12,20,28 seeds=4,17,42 order=paired"
  echo "Set RUN=TRUE after dataset-specific resource admission."
  exit 0
fi

[[ ! -e "${out_dir}" ]] || {
  echo "Refusing to reuse result directory: ${out_dir}" >&2; exit 1;
}
[[ -z "$(git -C "${package_root}" status --short)" ]] || {
  echo "Package source is dirty; use a clean identified revision." >&2; exit 1;
}
developer_tools="$(xcodebuild -version 2>/dev/null || true)"
if [[ "${developer_tools}" != Xcode* ]]; then
  clang_path="$(xcrun --find clang 2>/dev/null)" || {
    echo "Apple Command Line Tools are required." >&2; exit 1;
  }
  developer_tools="CommandLineTools:${clang_path}"
fi
mkdir -p "${out_dir}" "${library}" "${input_root}" \
  "${campaign_root}/tmp" "${campaign_root}/cache"
for working_dir in "${out_dir}" "${library}" "${input_root}" \
  "${campaign_root}/tmp" "${campaign_root}/cache"; do
  resolved="$(cd "${working_dir}" && pwd -P)"
  case "${resolved}" in
    "${stefano}"/*) ;;
    *) echo "Working path escapes Stefano: ${working_dir}" >&2; exit 1 ;;
  esac
done
python3 "${preflight}" --campaign-root "${campaign_root}" \
  --dataset "${dataset}" --verify-hash > "${out_dir}/input_preflight.json"
IFS=$'\t' read -r expected_input_path expected_input_sha < <(
  python3 - "${out_dir}/input_preflight.json" <<'PY'
import json
import sys

row = json.load(open(sys.argv[1]))["inputs"][0]
print(row["path"] + "\t" + row["sha256"])
PY
)
[[ -f "${expected_input_path}" &&
   "${expected_input_sha}" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Missing verified input identity." >&2; exit 1;
}
export FASTEMBEDR_MAC_EXPECTED_INPUT_PATH="${expected_input_path}"
export FASTEMBEDR_MAC_EXPECTED_INPUT_SHA256="${expected_input_sha}"

free_kib="$(df -Pk "${campaign_root}" | awk 'NR == 2 {print $4}')"
min_free_gib="${MIN_FREE_GIB:-80}"
[[ "${free_kib}" =~ ^[0-9]+$ && "${min_free_gib}" =~ ^[0-9]+$ ]] || {
  echo "Invalid free-space observation or minimum." >&2; exit 1;
}
(( min_free_gib >= 20 )) || {
  echo "The minimum free-space reserve cannot be below 20 GiB." >&2
  exit 1
}
(( free_kib >= min_free_gib * 1024 * 1024 )) || {
  echo "Less than ${min_free_gib} GiB free on Mac storage." >&2; exit 1;
}
free_pct="$(memory_pressure -Q 2>/dev/null | awk -F: '
  /System-wide memory free percentage/ {
    gsub(/[^0-9.]/, "", $2); print $2; exit
  }')"
[[ "${free_pct}" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  echo "Cannot measure Mac free-memory percentage." >&2; exit 1;
}
awk -v free="${free_pct}" 'BEGIN { exit !(free >= 75) }' || {
  echo "Mac free memory is below the 75% start gate." >&2; exit 1;
}

export TMPDIR="${campaign_root}/tmp"
export XDG_CACHE_HOME="${campaign_root}/cache"
export R_MAKEVARS_USER="${campaign_root}/toolchain/Makevars"
export LIBOMP_HOME="${campaign_root}/toolchain/libomp"
export R_LIBS_USER="${library}:${campaign_root}/Rlib"
export FASTEMBEDR_MAC_GUARD=TRUE
export OMP_NUM_THREADS=28 OPENBLAS_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 RCPP_PARALLEL_NUM_THREADS=28

sources=(
  "${bench_r}"
  "${benchmark_root}/benchmarks/shared/publication_metrics.R"
  "${benchmark_root}/benchmarks/shared/benchmark_worker_monitor.sh"
  "${script_dir}/mac_memory_guard_v1.py"
  "${benchmark_root}/benchmarks/shared/reference_opentsne_affinity.py"
  "${preflight}"
  "${script_dir}/M3_ULTRA_LOCAL_INPUTS_SHA256_20261101.txt"
  "${script_dir}/audit_m3_ultra_panel_v1.py"
  "${script_dir}/audit_m3_ultra_panel_quality_v1.R"
  "${script_dir}/mac_global_knn_recall_v1.R"
  "${script_dir}/smoke_m3_ultra_routes_v3.R"
  "$0"
)
shasum -a 256 "${sources[@]}" > "${out_dir}/source_hashes_before.txt"
{
  echo "dataset=${dataset}"
  echo "free_kib_at_start=${free_kib}"
  echo "free_memory_pct_at_start=${free_pct}"
  echo "system_swap_at_start=$(sysctl vm.swapusage)"
  echo "developer_tools=${developer_tools//$'\n'/; }"
  echo "package_archive_sha256=${archive_sha}"
  echo "package_commit=$(git -C "${package_root}" rev-parse HEAD)"
  echo "benchmark_commit=$(git -C "${benchmark_root}" rev-parse HEAD)"
  echo "benchmark_status_sha256=$(git -C "${benchmark_root}" status --short | shasum -a 256 | cut -d ' ' -f 1)"
  cat "${out_dir}/source_hashes_before.txt"
} > "${out_dir}/source_identity.txt"

R CMD INSTALL --preclean --library="${library}" "${archive}" \
  > "${out_dir}/install.log" 2>&1
installed_dll="${library}/fastEmbedR/libs/fastEmbedR.so"
shasum -a 256 "${installed_dll}" > "${out_dir}/dll_sha256_before.txt"
export FASTEMBEDR_MAC_EXPECTED_LIBRARY="${library}"
export FASTEMBEDR_RELEASE_COMMIT="$(git -C "${package_root}" rev-parse HEAD)"
export FASTEMBEDR_BENCHMARK_COMMIT="$(git -C "${benchmark_root}" rev-parse HEAD)"
export FASTEMBEDR_RELEASE_TAG="mac-source-${FASTEMBEDR_RELEASE_COMMIT:0:12}"
export FASTEMBEDR_RELEASE_VERSION="$(Rscript -e \
  'cat(as.character(packageVersion("fastEmbedR")))')"
export FASTEMBEDR_DLL_SHA256="$(cut -d ' ' -f 1 \
  "${out_dir}/dll_sha256_before.txt")"
export FASTEMBEDR_SOURCE_ARCHIVE_SHA256="${archive_sha}"
export FASTEMBEDR_PACKAGE_TARBALL_SHA256="${archive_sha}"
export FASTEMBEDR_ENFORCE_RELEASE_LOCK=FALSE
export FASTEMBEDR_ENFORCE_MAC_LOCK=TRUE
{
  echo "installed_version=${FASTEMBEDR_RELEASE_VERSION}"
  echo "installed_dll_sha256=${FASTEMBEDR_DLL_SHA256}"
  echo "private_library=${library}"
} >> "${out_dir}/source_identity.txt"
Rscript "${script_dir}/smoke_m3_ultra_routes_v3.R" "${out_dir}" \
  > "${out_dir}/capabilities.log" 2>&1

Rscript "${bench_r}" \
  --backend-group=local --base-dir="${benchmark_root}" \
  --data-root="${data_root}" --out-dir="${out_dir}" \
  --layout-dir="${out_dir}/layouts" \
  --input-dir="${input_root}" --cache-dir="${input_root}/precomputed" \
  --datasets="${dataset}" --methods="${methods}" \
  --threads-grid=1,4,8,12,20,28 --seeds=4,17,42 \
  --run-order=paired --order-seed=31031 \
  --strict-mac-memory=TRUE --blas-threads=1 \
  --local-cpu-max-n=2147483647 --local-cpu-exceptions="${dataset}" \
  --k=30 --perplexity=30 --quality-max-distance-ops=200000000 \
  --global-knn-recall-n=64 \
  --timeout=43200 --force=FALSE

shasum -a 256 "${sources[@]}" > "${out_dir}/source_hashes_after.txt"
cmp "${out_dir}/source_hashes_before.txt" \
  "${out_dir}/source_hashes_after.txt"
shasum -a 256 "${installed_dll}" > "${out_dir}/dll_sha256_after.txt"
cmp "${out_dir}/dll_sha256_before.txt" \
  "${out_dir}/dll_sha256_after.txt"
[[ "$(shasum -a 256 "${archive}" | cut -d' ' -f1)" == \
   "${archive_sha}" && \
   "$(git -C "${package_root}" rev-parse HEAD)" == \
   "${FASTEMBEDR_RELEASE_COMMIT}" &&
   -z "$(git -C "${package_root}" status --short)" ]] || {
  echo "Package source changed during the Mac benchmark." >&2; exit 1;
}
python3 "${preflight}" --campaign-root "${campaign_root}" \
  --dataset "${dataset}" --verify-hash > "${out_dir}/input_postflight.json"
python3 "${script_dir}/audit_m3_ultra_panel_v1.py" \
  "${out_dir}/benchmark_runs.csv" "${dataset}" \
  > "${out_dir}/panel_audit.json"
Rscript "${script_dir}/audit_m3_ultra_panel_quality_v1.R" \
  "${out_dir}" "${dataset}" --global-knn-recall \
  > "${out_dir}/quality_audit.log" 2>&1
echo "Execution and quality audits completed: ${out_dir}"
