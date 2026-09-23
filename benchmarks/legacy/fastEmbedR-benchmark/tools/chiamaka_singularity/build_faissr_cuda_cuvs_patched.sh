#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/mnt/sata_ssd/fastEmbedR/singularity}"
PATCH_ROOT="${PATCH_ROOT:-/mnt/sata_ssd/cuvs_nndescent_shmem_patch_20260625_175420}"
IMAGE_NAME="${IMAGE_NAME:-faissr_cuda_cuvs_patched.sif}"
DEF_NAME="${DEF_NAME:-faissr_cuda_cuvs_patched.def}"
BUILD_CMD="${BUILD_CMD:-apptainer build --force}"
LOG="${BASE_DIR}/build_faissr_cuda_cuvs_patched_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${BASE_DIR}/patched_libs"
cd "${BASE_DIR}"

echo "Using patched cuVS root: ${PATCH_ROOT}"
echo "Available patched cuVS libraries:"
find "${PATCH_ROOT}" -name "libcuvs*.so*" | sort

LIBCUVS="$(find "${PATCH_ROOT}" -name "libcuvs.so" -type f | head -1)"
LIBCUVS_C="$(find "${PATCH_ROOT}" -name "libcuvs_c.so" -type f | head -1)"

if [[ -z "${LIBCUVS}" || -z "${LIBCUVS_C}" ]]; then
  echo "Could not find both libcuvs.so and libcuvs_c.so under ${PATCH_ROOT}" >&2
  exit 1
fi

cp -L "${LIBCUVS}" "${BASE_DIR}/patched_libs/libcuvs.so"
cp -L "${LIBCUVS_C}" "${BASE_DIR}/patched_libs/libcuvs_c.so"
ls -lh "${BASE_DIR}/patched_libs/libcuvs.so" "${BASE_DIR}/patched_libs/libcuvs_c.so"

echo "Building ${IMAGE_NAME}"
${BUILD_CMD} "${BASE_DIR}/${IMAGE_NAME}" "${BASE_DIR}/${DEF_NAME}" 2>&1 | tee "${LOG}"

echo "Validating faissR/cuVS availability"
apptainer exec --nv "${BASE_DIR}/${IMAGE_NAME}" \
Rscript -e 'library(faissR); print(backend_info()); stopifnot(cuvs_available())'

echo "Validating patched cuVS NN-descent bug case"
apptainer exec --nv "${BASE_DIR}/${IMAGE_NAME}" Rscript -e '
library(faissR)
set.seed(1)
x <- matrix(runif(1440 * 16384), nrow = 1440)
ans <- nn(x, k = 10, backend = "cuda", method = "nndescent",
          metric = "euclidean", exclude_self = TRUE)
print(dim(ans$indices))
print(attr(ans, "backend"))
stopifnot(identical(dim(ans$indices), c(1440L, 10L)))
'

echo "DONE"
echo "Image: ${BASE_DIR}/${IMAGE_NAME}"
echo "Log:   ${LOG}"
