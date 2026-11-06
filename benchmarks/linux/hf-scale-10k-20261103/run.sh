#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: run.sh PATCH_XZ_BASE64 TESTS_XZ_BASE64" >&2
    exit 2
fi
work=/tmp/fastembedr-hf-scale10k
mkdir -p "$work/inputs" "$work/outputs"
printf '%s' "$1" | base64 -d > "$work/inputs/candidate.patch.xz"
printf '%s' "$2" | base64 -d > "$work/inputs/tests.tar.xz"
printf '%s  %s\n' \
    968a7b9e14e460daaf94c771e9b85d11b6d41ea003a0baea054a9def342aaa4f \
    "$work/inputs/candidate.patch.xz" \
    92f83b570cd4b2bc3ce6c85809be4334fba7bcd9d21ce55c20d5c125f5ac5f7d \
    "$work/inputs/tests.tar.xz" | sha256sum -c -
python - "$work/inputs" <<'PYLZMA'
import lzma
from pathlib import Path
import sys
root = Path(sys.argv[1])
for name in ("candidate.patch", "tests.tar"):
    (root / name).write_bytes(lzma.decompress((root / (name + ".xz")).read_bytes()))
PYLZMA
tar -xf "$work/inputs/tests.tar" -C "$work/inputs"
git clone -q https://github.com/tkcaccia/fastEmbedR.git "$work/fastEmbedR"
git -C "$work/fastEmbedR" checkout -q \
    4571fe483e29a528b4b837b5c9f5cefe509fac7b
git -C "$work/fastEmbedR" apply --check "$work/inputs/candidate.patch"
git -C "$work/fastEmbedR" apply "$work/inputs/candidate.patch"
git -C "$work/fastEmbedR" diff --check
git clone -q https://github.com/tkcaccia/faissR.git "$work/faissR"
git -C "$work/faissR" checkout -q \
    7a22de471eb6d83dd9d1873ef0f89401ea8f11f5
git clone -q https://github.com/tkcaccia/gpuinfo.git "$work/gpuinfo"
git -C "$work/gpuinfo" checkout -q \
    a1122acf1cdf59c2fb2e19283353f3231d85bde3
printf 'SOURCE_BASE=%s\nSOURCE_PATCH=%s\n' \
    "$(git -C "$work/fastEmbedR" rev-parse HEAD)" \
    "$(sha256sum "$work/inputs/candidate.patch.xz" | cut -d ' ' -f 1)"
printf 'FAISSR_COMMIT=%s\nGPUINFO_COMMIT=%s\n' \
    "$(git -C "$work/faissR" rev-parse HEAD)" \
    "$(git -C "$work/gpuinfo" rev-parse HEAD)"

prefix=$work/r
mamba create -y -p "$prefix" --override-channels \
    -c conda-forge r-base=4.6.1 'faiss-cpu>=1.11' libuv pkg-config \
    > "$work/outputs/mamba-r.log" 2>&1 || {
        tail -n 60 "$work/outputs/mamba-r.log"
        exit 1
    }
mamba create -y -p "$work/tools" --override-channels \
    -c conda-forge make binutils gxx_linux-64=14 \
    > "$work/outputs/mamba-tools.log" 2>&1 || {
        tail -n 60 "$work/outputs/mamba-tools.log"
        exit 1
    }
export PATH="$work/tools/bin:$prefix/bin:$PATH"
export LD_LIBRARY_PATH="$prefix/lib:/opt/conda/lib:${LD_LIBRARY_PATH:-}"
export FAISS_HOME="$prefix"
export CUDA_HOME=/opt/conda CUVS_HOME=/opt/conda
export CUDAHOSTCXX=$work/tools/bin/x86_64-conda-linux-gnu-g++
export FASTEMBEDR_CUGRAPH_PYTHON=/opt/conda/bin/python
export MAKEFLAGS=-j4
"$FASTEMBEDR_CUGRAPH_PYTHON" -c \
    'import cudf, cugraph, dask_cuda'
git clone -q https://github.com/NVIDIA/nccl-tests.git \
    "$work/nccl-tests"
git -C "$work/nccl-tests" checkout -q \
    afd59abab774a6a4b492eb344bd0c845a0b7bb4d
make -C "$work/nccl-tests" -j4 CUDA_HOME="$CUDA_HOME" \
    NCCL_HOME="$CUDA_HOME" \
    NVCC_GENCODE='-gencode=arch=compute_86,code=sm_86' \
    CXX="$CUDAHOSTCXX" \
    > "$work/outputs/nccl-build.log" 2>&1 || {
        tail -n 60 "$work/outputs/nccl-build.log"
        exit 1
    }
if ldd "$work/nccl-tests/build/all_reduce_perf" | \
        grep -q 'not found'; then
    echo "NCCL test binary has unresolved libraries." >&2
    exit 1
fi
Rscript -e 'install.packages(c("Rcpp", "withr", "float", "jsonlite"),
    repos = "https://cloud.r-project.org")' \
    > "$work/outputs/r-dependencies.log" 2>&1 || {
        tail -n 60 "$work/outputs/r-dependencies.log"
        exit 1
    }
R CMD INSTALL "$work/gpuinfo" \
    > "$work/outputs/gpuinfo-install.log" 2>&1 || {
        tail -n 60 "$work/outputs/gpuinfo-install.log"
        exit 1
    }
FAISSR_USE_CUDA=0 FAISSR_USE_CUVS=0 \
    R CMD INSTALL "$work/faissR" \
    > "$work/outputs/faissr-install.log" 2>&1 || {
        tail -n 80 "$work/outputs/faissr-install.log"
        exit 1
    }

mamba install -y -p "$CUDA_HOME" --no-deps \
    --override-channels -c nvidia libcufft-dev=11.3.3.83 \
    > "$work/outputs/cufft-install.log" 2>&1 || {
        tail -n 60 "$work/outputs/cufft-install.log"
        exit 1
    }
export FASTEMBEDR_USE_CUDA=1 FASTEMBEDR_USE_CUVS=1
export FASTEMBEDR_USE_NCCL=1 FASTEMBEDR_REQUIRE_CUDA=1
export FASTEMBEDR_CUDA_ARCH=86
R CMD INSTALL "$work/fastEmbedR" \
    > "$work/outputs/fastembedr-install.log" 2>&1 || {
        tail -n 100 "$work/outputs/fastembedr-install.log"
        exit 1
    }
tail -n 15 "$work/outputs/fastembedr-install.log"
Rscript -e 'stopifnot(
    packageVersion("faissR") == "0.1",
    packageVersion("gpuinfo") == "0.2.0",
    packageVersion("fastEmbedR") == "0.1",
    fastEmbedR:::massive_cuda_device_count_cpp() == 2L,
    fastEmbedR:::massive_nccl_available_cpp(),
    fastEmbedR:::native_cuda_knn_available_cpp())'
sha256sum "$prefix/lib/R/library/fastEmbedR/libs/fastEmbedR.so"
nvidia-smi --query-gpu=index,uuid,name,memory.total,driver_version \
    --format=csv,noheader

check_cleanup() {
    local active attempt
    for attempt in {1..10}; do
        active=$(timeout 5s nvidia-smi --query-compute-apps=pid \
            --format=csv,noheader,nounits) || return 1
        if [ -z "$active" ]; then return 0; fi
        sleep 1
    done
    printf 'GPU contexts remain: %s\n' "$active" >&2
    return 1
}

run_case() {
    local label=$1 status=0
    shift
    echo "CASE_START $label $(date -u +%FT%TZ)"
    timeout -s TERM -k 10s 120s "$@" \
        > "$work/outputs/$label.log" 2>&1 || status=$?
    if ! check_cleanup; then
        echo "CASE_UNSAFE_CLEANUP $label" >&2
        return 1
    fi
    if [ "$status" -ne 0 ]; then
        tail -n 70 "$work/outputs/$label.log" >&2
        echo "CASE_FAIL $label exit=$status" >&2
        return "$status"
    fi
    tail -n 12 "$work/outputs/$label.log"
    echo "CASE_PASS $label $(date -u +%FT%TZ)"
}

run_case nccl_all_reduce "$work/nccl-tests/build/all_reduce_perf" \
    -b 8 -e 16M -f 2 -g 2 -c 1
run_case nccl_all_gather "$work/nccl-tests/build/all_gather_perf" \
    -b 8 -e 16M -f 2 -g 2 -c 1
export FASTEMBEDR_K=30 FASTEMBEDR_UMAP_EPOCHS=20
export FASTEMBEDR_TSNE_ITER=15 FASTEMBEDR_CHUNK_ROWS=2048
mkdir -p "$work/optimizer"
FASTEMBEDR_ROWS=10000 Rscript "$work/inputs/optimizers.R" \
    prepare "$work/optimizer" "$work/outputs"
run_case umap_gpu1 Rscript "$work/inputs/optimizers.R" fit \
    "$work/optimizer" "$work/outputs" umap 0 umap_gpu1
run_case umap_gpu2 Rscript "$work/inputs/optimizers.R" fit \
    "$work/optimizer" "$work/outputs" umap 0,1 umap_gpu2
run_case tsne_gpu1 Rscript "$work/inputs/optimizers.R" fit \
    "$work/optimizer" "$work/outputs" tsne 0 tsne_gpu1
run_case tsne_gpu2 Rscript "$work/inputs/optimizers.R" fit \
    "$work/optimizer" "$work/outputs" tsne 0,1 tsne_gpu2
run_case compare Rscript "$work/inputs/optimizers.R" compare \
    "$work/optimizer" "$work/outputs"
for table in "$work/outputs"/*.csv; do
    echo "RESULT_TABLE $(basename "$table")"
    cat "$table"
done
sha256sum "$work/outputs"/*.csv
echo CUDA_10K_TWO_GPU_QUALIFICATION_PASS
