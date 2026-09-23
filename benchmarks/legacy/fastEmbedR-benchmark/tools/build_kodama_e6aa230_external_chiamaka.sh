#!/usr/bin/env bash

set -euo pipefail

IMAGE="${IMAGE:-/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.sif}"
ROOT="${ROOT:-/mnt/sata_ssd/fastEmbedR/kodama_validation/e6aa230}"
COMMIT="${COMMIT:-e6aa230d96fd526e2af22cf244cbde58c6e7e723}"
SOURCE="${ROOT}/kodama-cpp"
BUILD="${SOURCE}/build-cuda"
PREFIX="${ROOT}/install"
R_LIBRARY="${ROOT}/R-library"

mkdir -p "${ROOT}" "${R_LIBRARY}"
if [[ ! -d "${SOURCE}/.git" ]]; then
  git clone https://github.com/tkcaccia/kodama-cpp.git "${SOURCE}"
fi
git -C "${SOURCE}" fetch --prune origin
git -C "${SOURCE}" checkout --detach "${COMMIT}"

singularity exec \
  --nv \
  --cleanenv \
  -B /mnt/sata_ssd:/mnt/sata_ssd \
  "${IMAGE}" \
  bash -lc "
    set -euo pipefail
    export PATH=/opt/conda/bin:/usr/local/cuda/bin:/usr/bin:/bin
    /opt/conda/bin/cmake -S '${SOURCE}' -B '${BUILD}' \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX='${PREFIX}' \
      -DCMAKE_MAKE_PROGRAM=/opt/conda/bin/make \
      -DCMAKE_CXX_COMPILER=/opt/conda/bin/x86_64-conda-linux-gnu-c++ \
      -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
      -DCMAKE_CUDA_ARCHITECTURES=120 \
      -DKODAMA_ENABLE_CUDA=ON \
      -DKODAMA_ENABLE_METAL=OFF \
      -DKODAMA_ENABLE_OPENMP=ON \
      -DKODAMA_BUILD_TESTS=OFF \
      -DKODAMA_BUILD_EXAMPLES=OFF
    /opt/conda/bin/cmake --build '${BUILD}' -j4
    /opt/conda/bin/cmake --install '${BUILD}'
    cd '${SOURCE}/split-repos/kodama-r'
    KODAMA_CPP_ROOT='${SOURCE}' \
    KODAMA_CPP_BUILD_DIR='${BUILD}' \
    KODAMA_R_CUDA_LIBS='-lcudart -lcublasLt -lcublas -lcusolver -lcusparse -lcurand -lcufft' \
    /opt/conda/bin/R CMD INSTALL -l '${R_LIBRARY}' .
    KODAMA_R_LIB='${R_LIBRARY}' /opt/conda/bin/Rscript -e \
      '.libPaths(c(Sys.getenv(\"KODAMA_R_LIB\"), .libPaths())); library(kodamaR); print(packageVersion(\"kodamaR\")); KODAMA.diagnostics()'
  "

printf 'source=%s\n' "${SOURCE}"
printf 'commit=%s\n' "$(git -C "${SOURCE}" rev-parse HEAD)"
printf 'build=%s\n' "${BUILD}"
printf 'prefix=%s\n' "${PREFIX}"
printf 'r_library=%s\n' "${R_LIBRARY}"
