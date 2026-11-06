#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: run.sh PATCH_BASE64_PART1 PATCH_BASE64_PART2 TESTS_BASE64" >&2
    exit 2
fi
work=/tmp/fastembedr-hf-mnist-quality
mkdir -p "$work/inputs" "$work/outputs"
printf '%s%s' "$1" "$2" | base64 -d > "$work/inputs/candidate.patch.xz"
printf '%s' "$3" | base64 -d > "$work/inputs/tests.tar.xz"
printf '%s  %s\n' \
    f5be1ad8b49cb5d60e164823a4bde6a2d3bf129d29debf5a012cf6a1cb4f159a \
    "$work/inputs/candidate.patch.xz" \
    9f0599d55001db7eb197ea5585ce18a6714b937e32ea6d8e777766fe991f133d \
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
run_case resident2d Rscript "$work/inputs/hf_validate_multi3d.R" resident2d
run_case resident3d Rscript "$work/inputs/hf_validate_multi3d.R" resident3d
run_case umap2d Rscript "$work/inputs/hf_validate_multi3d.R" umap2d
run_case umap3d Rscript "$work/inputs/hf_validate_multi3d.R" umap3d
run_case pca Rscript "$work/inputs/hf_validate_multi3d.R" pca
run_case pca_landmark Rscript "$work/inputs/hf_validate_multi3d.R" pca_landmark
run_case cluster Rscript "$work/inputs/hf_validate_multi3d.R" cluster
run_case file3d Rscript "$work/inputs/hf_validate_multi3d.R" file3d
python - "$work/inputs" <<'PYDIGITS'
import numpy as np
import io
import urllib.request
import hashlib
from pathlib import Path
import sys
url = 'https://storage.googleapis.com/tensorflow/tf-keras-datasets/mnist.npz'
with urllib.request.urlopen(url, timeout=45) as response:
    archive = response.read()
print('MNIST_ARCHIVE_SHA256', hashlib.sha256(archive).hexdigest())
with np.load(io.BytesIO(archive)) as data:
    images = data['x_train']
    labels = data['y_train']
rng = np.random.default_rng(42)
indices = np.concatenate([rng.choice(np.flatnonzero(labels == i),
                                    size=30, replace=False)
                          for i in range(10)])
root = Path(sys.argv[1])
(images[indices].reshape(300, 784).astype('<f4') / 255).tofile(
    root / 'digits.f32')
labels[indices].astype('<i4').tofile(root / 'digits.i32')
print('MNIST_DATASET 300x784 balanced seed 42')
PYDIGITS
sha256sum "$work/inputs/digits.f32" "$work/inputs/digits.i32"
for quality_case in embed_tsne_2d embed_tsne_3d \
    embed_umap_2d embed_umap_3d cluster; do
    echo "CASE_START $quality_case $(date -u +%FT%TZ)"
    timeout -s TERM -k 10s 300s Rscript \
        "$work/inputs/hf_quality_digits.R" \
        "$work/inputs/common.R" "$quality_case" \
        > "$work/outputs/$quality_case.log" 2>&1 || {
            status=$?
            tail -n 100 "$work/outputs/$quality_case.log"
            echo "CASE_FAIL $quality_case exit=$status"
            exit "$status"
        }
    check_cleanup
    cat "$work/outputs/$quality_case.log"
    echo "CASE_PASS $quality_case $(date -u +%FT%TZ)"
done
echo CUDA_TWO_GPU_MNIST_QUALITY_CHECK_PASS
