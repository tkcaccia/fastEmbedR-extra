#!/usr/bin/env bash

set -euo pipefail

script_path="${BASH_SOURCE[0]:-$0}"
script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
benchmark_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
package_root="${FASTEMBEDR_PACKAGE_ROOT:-/Users/stefano/Documents/umap}"
hpc_root="${HPC_ROOT:-/Users/stefano/HPC-firenze/NN}"
target="${hpc_root}/current_fastembedr_validation"

# shellcheck disable=SC1091
source "${script_dir}/release_lock.env"

[[ -d "${hpc_root}" ]] || { echo "HPC mirror is unavailable: ${hpc_root}" >&2; exit 1; }
[[ -d "${package_root}/.git" ]] || { echo "Package checkout is unavailable: ${package_root}" >&2; exit 1; }

package_commit="$(git -C "${package_root}" rev-parse HEAD)"
[[ "${package_commit}" == "${FASTEMBEDR_RELEASE_COMMIT}" ]] || {
  echo "Package commit mismatch: expected ${FASTEMBEDR_RELEASE_COMMIT}, found ${package_commit}" >&2
  exit 1
}
[[ -z "$(git -C "${package_root}" status --short)" ]] || {
  echo "Package checkout is dirty; refusing to synchronize a release." >&2
  git -C "${package_root}" status --short >&2
  exit 1
}

benchmark_commit="$(git -C "${benchmark_root}" rev-parse HEAD)"
[[ -z "$(git -C "${benchmark_root}" status --short)" ]] || {
  echo "Benchmark checkout is dirty; commit it before synchronization." >&2
  git -C "${benchmark_root}" status --short >&2
  exit 1
}

mkdir -p "${target}"
for path in "${script_dir}"/*; do
  [[ -f "${path}" ]] || continue
  cp -p "${path}" "${target}/"
done
printf '%s\n' "${benchmark_commit}" > "${target}/benchmark_commit.txt"

source_tmp="${target}/source.new.$$"
rm -rf "${source_tmp}"
git clone --quiet --no-local "${package_root}" "${source_tmp}"
git -C "${source_tmp}" checkout --quiet --detach "${FASTEMBEDR_RELEASE_COMMIT}"
rm -rf "${target}/source"
mv "${source_tmp}" "${target}/source"

chmod +x "${target}"/*.sh
cat <<EOF
Synchronized immutable fastEmbedR validation bundle.
  package version:   ${FASTEMBEDR_RELEASE_VERSION}
  package commit:    ${FASTEMBEDR_RELEASE_COMMIT}
  benchmark commit:  ${benchmark_commit}
  destination:       ${target}

No Slurm jobs were submitted.
EOF
