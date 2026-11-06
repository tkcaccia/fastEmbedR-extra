#!/bin/bash
# Serial, fail-closed, fully local Mac queue. No HPC or remote dependency.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
run="${campaign}/deep1b-100m-v1"
queue="${run}/queue100m"
panel="${campaign}/results/m3-ultra-panel-v1-queue"
panel_exit="${panel}/panel_v5b_20261102.launch.exit"
input="${campaign}/data/BigANN/deep/mod10-100000000/base.mod10.100000000.fbin"
archive="${campaign}/candidates/mac-benchmark-integration-20261102-v3/fastEmbedR_0.1.tar.gz"
archive_sha=ae37cd4f3638ec59d515456e5c6e0c1bf6d38de8fba05414aab471a0abd76e00
input_sha=259e5ed58e0218790bec8e8514c011f39bfd839c012d8d818d9106773ffeac94
test ! -e "${queue}"
mkdir -p "${queue}" "${run}/Rlib" "${run}/cases"
trap 'code=$?; printf "%s\n" "${code}" > "${queue}/queue.exit"' EXIT
printf 'stage,status,seconds\n' > "${queue}/status.csv"
for attempt in $(seq 1 10080); do
  [[ -e "${panel_exit}" ]] && break
  sleep 60
done
[[ -e "${panel_exit}" && "$(cat "${panel_exit}")" == 0 ]] || {
  echo "The prior Mac panel did not finish successfully." >&2
  exit 1
}
[[ -z "$(pgrep -x 'R|Rscript' || true)" ]] || {
  echo "Another R worker is active." >&2; exit 1;
}
[[ -f "${input}" && ! -f "${campaign}/data/BigANN/deep/1000000000/base.1000000000.fbin" ]] || {
  echo "Verified subset or full-source retirement is missing." >&2
  exit 1
}
[[ "$(cat "${run}/retire.exit")" == 0 ]] || exit 1
[[ "$(shasum -a 256 "${input}" | awk '{print $1}')" == "${input_sha}" ]] || exit 1
[[ "$(shasum -a 256 "${archive}" | awk '{print $1}')" == "${archive_sha}" ]] || exit 1
source_files=("${run}/benchmark/deep1b_mod10_100m_worker_v1.R"
  "${run}/benchmark/mac_long_guard_v1.py" "$0")
shasum -a 256 "${source_files[@]}" > "${queue}/sources.lock"
input_stamp="$(stat -f '%z:%m' "${input}")"
disk_device="$(df -P "${run}" | awk 'NR == 2 {print $1}')"
physical_store="$(diskutil info "${disk_device}" |
  awk -F: '/APFS Physical Store:/ {
    gsub(/[[:space:]]/, "", $2); print $2; exit
  }')"
[[ "${physical_store}" =~ ^disk[0-9]+s[0-9]+$ ]] || exit 1
physical_disk="${physical_store%s[0-9]*}"
printf 'input_sha256=%s\narchive_sha256=%s\nphysical_disk=%s\n' \
  "${input_sha}" "${archive_sha}" "${physical_disk}" \
  > "${queue}/identity.txt"
export TMPDIR="${campaign}/tmp"
export XDG_CACHE_HOME="${campaign}/cache"
export R_MAKEVARS_USER="${campaign}/toolchain/Makevars"
export LIBOMP_HOME="${campaign}/toolchain/libomp"
export R_LIBS_USER="${run}/Rlib:${campaign}/Rlib"
export OPENBLAS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1
export MKL_NUM_THREADS=1
R CMD INSTALL --preclean --library="${run}/Rlib" "${archive}" \
  > "${queue}/install.log" 2>&1
shasum -a 256 "${run}/Rlib/fastEmbedR/libs/fastEmbedR.so" \
  > "${queue}/installed_dll.sha256"
stages=(smoke_fullgraph pca_cpu1 pca_cpu8 pca_cpu20 pca_cpu28 pca_metal
  knn_cpu20 tsne_affinity tsne_cpu20 umap_fuzzy umap_metal
  umap_cpu20 umap_cpu1 leiden_cpu)
for stage in "${stages[@]}"; do
  [[ "$(stat -f '%z:%m' "${input}")" == "${input_stamp}" ]] || exit 1
  shasum -a 256 "${source_files[@]}" > "${queue}/sources.current"
  cmp "${queue}/sources.lock" "${queue}/sources.current" || exit 1
  [[ -z "$(pgrep -x 'R|Rscript' || true)" ]] || exit 1
  free_kib="$(df -Pk "${run}" | awk 'NR == 2 {print $4}')"
  (( free_kib >= 200 * 1024 * 1024 )) || {
    echo "Mac free space fell below the 200 GiB stage reserve." >&2
    exit 1
  }
  stage_root="${queue}/${stage}"
  mkdir -p "${stage_root}"
  iostat -Id "${physical_disk}" > "${stage_root}/disk_before.txt"
  started="$(date +%s)"
  export OMP_NUM_THREADS=20 RCPP_PARALLEL_NUM_THREADS=20
  status=0
  /usr/bin/python3 -u "${run}/benchmark/mac_long_guard_v1.py" \
    3888000 "${stage_root}/guard.json" \
    /usr/bin/time -l -o "${stage_root}/time.txt" \
    Rscript "${run}/benchmark/deep1b_mod10_100m_worker_v1.R" \
    "${stage}" "${run}" \
    > "${stage_root}/worker.log" 2>&1 || status=$?
  iostat -Id "${physical_disk}" > "${stage_root}/disk_after.txt"
  elapsed=$(( $(date +%s) - started ))
  if [[ "${status}" != 0 ||
        ! -f "${run}/cases/${stage}/result.rds" ]]; then
    printf '%s,failed,%s\n' "${stage}" "${elapsed}" \
      >> "${queue}/status.csv"
    exit 1
  fi
  printf '%s,success,%s\n' "${stage}" "${elapsed}" \
    >> "${queue}/status.csv"
done
printf 'queue,success,0\n' >> "${queue}/status.csv"
