#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=32G
#SBATCH --time=03:00:00
#SBATCH --job-name=feR_current_build
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_current_build_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_current_build_%j.err

set -euo pipefail

BASE_DIR=/scratch/firenze/NN
BUNDLE_DIR="${BASE_DIR}/current_fastembedr_validation"
IMAGE="${BASE_DIR}/singularity/fastembedr_cuda.sif"
SOURCE_DIR="${BUNDLE_DIR}/source"
PACKAGE_SOURCE="${BUNDLE_DIR}/package_source"
RELEASE_LOCK="${BUNDLE_DIR}/release_lock.env"

[[ -f "${RELEASE_LOCK}" ]] || { echo "Missing release lock: ${RELEASE_LOCK}" >&2; exit 1; }
# shellcheck disable=SC1090
source "${RELEASE_LOCK}"

: "${FASTEMBEDR_RELEASE_TAG:?Set FASTEMBEDR_RELEASE_TAG in release_lock.env}"
: "${FASTEMBEDR_RESULT_DOI:?Set FASTEMBEDR_RESULT_DOI in release_lock.env}"

[[ -f "${IMAGE}" ]] || { echo "Missing image: ${IMAGE}" >&2; exit 1; }
[[ -d "${SOURCE_DIR}/.git" ]] || {
  echo "Missing current source checkout: ${SOURCE_DIR}" >&2
  exit 1
}

source_commit="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
[[ "${source_commit}" == "${FASTEMBEDR_RELEASE_COMMIT}" ]] || {
  echo "Release lock mismatch: expected ${FASTEMBEDR_RELEASE_COMMIT}, found ${source_commit}" >&2
  exit 1
}
[[ -z "$(git -C "${SOURCE_DIR}" status --short)" ]] || {
  echo "Release source checkout is dirty; refusing to benchmark." >&2
  git -C "${SOURCE_DIR}" status --short >&2
  exit 1
}
source_version="$(sed -n 's/^Version:[[:space:]]*//p' "${SOURCE_DIR}/DESCRIPTION")"
[[ "${source_version}" == "${FASTEMBEDR_RELEASE_VERSION}" ]] || {
  echo "Version mismatch: expected ${FASTEMBEDR_RELEASE_VERSION}, found ${source_version}" >&2
  exit 1
}

mkdir -p "${BASE_DIR}/benchmark_logs" "${BUNDLE_DIR}/Rlib"

CONTAINER="$(command -v apptainer || command -v singularity || true)"
[[ -n "${CONTAINER}" ]] || {
  echo "apptainer/singularity is unavailable" >&2
  exit 1
}

rm -rf "${PACKAGE_SOURCE}" "${BUNDLE_DIR}/fastEmbedR_${FASTEMBEDR_RELEASE_VERSION}.tar.gz"
mkdir -p "${PACKAGE_SOURCE}"
git -C "${SOURCE_DIR}" archive "${FASTEMBEDR_RELEASE_COMMIT}" | tar -x -C "${PACKAGE_SOURCE}"

source_archive="${BUNDLE_DIR}/${FASTEMBEDR_RELEASE_LABEL}-source.tar.gz"
git -C "${SOURCE_DIR}" archive --format=tar.gz \
  --output="${source_archive}" "${FASTEMBEDR_RELEASE_COMMIT}"
source_archive_sha256="$(sha256sum "${source_archive}" | awk '{print $1}')"
image_sha256="$(sha256sum "${IMAGE}" | awk '{print $1}')"
benchmark_commit_file="${BUNDLE_DIR}/benchmark_commit.txt"
[[ -s "${benchmark_commit_file}" ]] || {
  echo "Missing benchmark commit identity: ${benchmark_commit_file}" >&2
  exit 1
}
benchmark_commit="$(tr -d '[:space:]' < "${benchmark_commit_file}")"
[[ "${benchmark_commit}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid benchmark commit identity: ${benchmark_commit}" >&2
  exit 1
}

"${CONTAINER}" exec \
  --bind "${BASE_DIR}:${BASE_DIR}" \
  --pwd "${BUNDLE_DIR}" \
  "${IMAGE}" \
  /opt/conda/bin/R CMD build --no-build-vignettes "${PACKAGE_SOURCE}"

"${CONTAINER}" exec \
  --bind "${BASE_DIR}:${BASE_DIR}" \
  --pwd "${BUNDLE_DIR}" \
  "${IMAGE}" \
  /bin/bash "${BUNDLE_DIR}/install_current_fastembedr_in_container.sh"

dll_path="$(find "${BUNDLE_DIR}/Rlib/fastEmbedR/libs" -maxdepth 1 \
  -type f -name 'fastEmbedR.so' -print -quit)"
[[ -n "${dll_path}" ]] || { echo "Installed fastEmbedR.so was not found." >&2; exit 1; }
dll_sha256="$(sha256sum "${dll_path}" | awk '{print $1}')"
package_tarball="${BUNDLE_DIR}/fastEmbedR_${FASTEMBEDR_RELEASE_VERSION}.tar.gz"
package_tarball_sha256="$(sha256sum "${package_tarball}" | awk '{print $1}')"

cat > "${BUNDLE_DIR}/validated_release_identity.env" <<EOF
FASTEMBEDR_RELEASE_TAG=${FASTEMBEDR_RELEASE_TAG}
FASTEMBEDR_RELEASE_VERSION=${FASTEMBEDR_RELEASE_VERSION}
FASTEMBEDR_RELEASE_COMMIT=${FASTEMBEDR_RELEASE_COMMIT}
FASTEMBEDR_RELEASE_LABEL=${FASTEMBEDR_RELEASE_LABEL}
FASTEMBEDR_SOURCE_ARCHIVE_SHA256=${source_archive_sha256}
FASTEMBEDR_PACKAGE_TARBALL_SHA256=${package_tarball_sha256}
FASTEMBEDR_DLL_SHA256=${dll_sha256}
FASTEMBEDR_IMAGE_SHA256=${image_sha256}
FASTEMBEDR_BENCHMARK_COMMIT=${benchmark_commit}
FASTEMBEDR_RESULT_DOI=${FASTEMBEDR_RESULT_DOI}
EOF

touch "${BUNDLE_DIR}/INSTALL_OK"
echo "Current fastEmbedR installation validated: ${BUNDLE_DIR}/Rlib"
cat "${BUNDLE_DIR}/validated_release_identity.env"
