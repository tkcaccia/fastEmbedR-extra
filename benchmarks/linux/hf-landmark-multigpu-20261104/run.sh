#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -ne 3 ]; then exit 2; fi
work=/tmp/fastembedr-hf-landmark-multigpu
mkdir -p "$work"
printf '%s%s%s' "$1" "$2" "$3" | base64 -d > "$work/source.patch.xz"
printf '%s  %s\n' \
  c05e5389d690ace23eb3241867c5c2259467d2c9eb4925eb7dbba919ce72704e \
  "$work/source.patch.xz" | sha256sum -c -
python3 - "$work" <<'PYLZMA'
import lzma
from pathlib import Path
import sys
root = Path(sys.argv[1])
(root / "source.patch").write_bytes(
    lzma.decompress((root / "source.patch.xz").read_bytes()))
PYLZMA
git clone -q https://github.com/tkcaccia/fastEmbedR.git "$work/fastEmbedR"
git -C "$work/fastEmbedR" checkout -q \
  4571fe483e29a528b4b837b5c9f5cefe509fac7b
git -C "$work/fastEmbedR" apply --check "$work/source.patch"
git -C "$work/fastEmbedR" apply "$work/source.patch"
git -C "$work/fastEmbedR" diff --check
git clone -q https://github.com/tkcaccia/faissR.git "$work/faissR"
git -C "$work/faissR" checkout -q \
  7a22de471eb6d83dd9d1873ef0f89401ea8f11f5
git clone -q https://github.com/tkcaccia/gpuinfo.git "$work/gpuinfo"
git -C "$work/gpuinfo" checkout -q \
  a1122acf1cdf59c2fb2e19283353f3231d85bde3
printf 'SOURCE_BASE=%s\nSOURCE_PATCH=%s\n' \
  "$(git -C "$work/fastEmbedR" rev-parse HEAD)" \
  "$(sha256sum "$work/source.patch.xz" | cut -d ' ' -f 1)"
prefix=$work/r
mamba create -y -p "$prefix" --override-channels \
  -c conda-forge r-base=4.6.1 'faiss-cpu>=1.11' libuv pkg-config \
  > "$work/mamba-r.log" 2>&1 || {
    tail -n 50 "$work/mamba-r.log"; exit 1;
  }
mamba create -y -p "$work/tools" --override-channels \
  -c conda-forge make binutils gxx_linux-64=14 \
  > "$work/mamba-tools.log" 2>&1 || {
    tail -n 50 "$work/mamba-tools.log"; exit 1;
  }
export PATH="$work/tools/bin:$prefix/bin:$PATH"
export LD_LIBRARY_PATH="$prefix/lib:/opt/conda/lib:${LD_LIBRARY_PATH:-}"
export FAISS_HOME="$prefix" CUDA_HOME=/opt/conda CUVS_HOME=/opt/conda
export CUDAHOSTCXX=$work/tools/bin/x86_64-conda-linux-gnu-g++
export MAKEFLAGS=-j4
Rscript -e 'install.packages(c("Rcpp", "withr", "float", "jsonlite"),
  repos = "https://cloud.r-project.org")' \
  > "$work/r-dependencies.log" 2>&1 || {
    tail -n 50 "$work/r-dependencies.log"; exit 1;
  }
R CMD INSTALL "$work/gpuinfo" > "$work/gpuinfo-install.log" 2>&1 || {
  tail -n 50 "$work/gpuinfo-install.log"; exit 1;
}
FAISSR_USE_CUDA=0 FAISSR_USE_CUVS=0 R CMD INSTALL "$work/faissR" \
  > "$work/faissr-install.log" 2>&1 || {
    tail -n 50 "$work/faissr-install.log"; exit 1;
  }
mamba install -y -p "$CUDA_HOME" --no-deps \
  --override-channels -c nvidia libcufft-dev=11.3.3.83 \
  > "$work/cufft-install.log" 2>&1 || {
    tail -n 50 "$work/cufft-install.log"; exit 1;
  }
export FASTEMBEDR_USE_CUDA=1 FASTEMBEDR_USE_CUVS=1
export FASTEMBEDR_USE_NCCL=1 FASTEMBEDR_REQUIRE_CUDA=1
export FASTEMBEDR_CUDA_ARCH=86
R CMD INSTALL "$work/fastEmbedR" > "$work/fastembedr-install.log" 2>&1 || {
  tail -n 100 "$work/fastembedr-install.log"; exit 1;
}
tail -n 8 "$work/fastembedr-install.log"
sha256sum "$prefix/lib/R/library/fastEmbedR/libs/fastEmbedR.so"
nvidia-smi --query-gpu=index,uuid,name,memory.total \
  --format=csv,noheader
status=0
timeout -s TERM -k 10s 90s Rscript - > "$work/test.log" 2>&1 <<'RS' || status=$?
library(fastEmbedR)
stopifnot(fastEmbedR:::massive_cuda_device_count_cpp() == 2L)
stopifnot(fastEmbedR:::massive_nccl_available_cpp())
set.seed(84)
x <- rbind(matrix(rnorm(80L * 8L, 0, 0.2), 80L, 8L),
           matrix(rnorm(80L * 8L, 3, 0.2), 80L, 8L))
for (dims in c(2L, 3L)) {
  fit <- tsne(x, landmarks = 80L, perplexity = 5,
    affinity_k = 15L, n_components = dims,
    early_exaggeration_iter = 2L, n_iter = 3L,
    transform_early_exaggeration_iter = 1L,
    transform_iter = 2L, auto_config = FALSE,
    backend = "cuda", devices = c(0L, 1L), seed = 84L)
  p <- fit$parameters
  stopifnot(identical(dim(fit$layout), c(160L, dims)))
  stopifnot(all(is.finite(fit$layout)))
  stopifnot(identical(p$transform_gpu_devices, c(0L, 1L)))
  stopifnot(length(p$transform_gpu_identity) == 2L)
  stopifnot(identical(as.integer(p$per_device_query_rows), c(40L, 40L)))
  stopifnot(identical(p$transform_optimizer,
    "opentsne_fixed_reference_cuda_query_shards"))
  stopifnot(max(abs(fit$layout[fit$landmarks$indices, , drop = FALSE] -
    fit$landmarks$layout)) < 1e-5)
  cat("LANDMARK_TSNE_MULTI_GPU_PASS", dims, "D\n")
}
RS
clean=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
    --format=csv,noheader,nounits) || break
  if [ -z "$contexts" ]; then clean=1; break; fi
  sleep 1
done
if [ "$clean" -ne 1 ]; then echo CLEANUP_UNKNOWN; exit 1; fi
if [ "$status" -ne 0 ]; then
  tail -n 80 "$work/test.log"
  echo "TEST_FAIL=$status"
  exit "$status"
fi
cat "$work/test.log"
echo LANDMARK_TSNE_MULTI_GPU_CHECK_PASS
