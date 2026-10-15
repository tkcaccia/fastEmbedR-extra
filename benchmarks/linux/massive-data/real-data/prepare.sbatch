#!/usr/bin/env bash
set -euo pipefail
suite=${REAL_SUITE:?}
root=${REAL_ROOT:?}
dataset=${REAL_DATASET:?}
base=${REAL_BASE:?}
image=$base/singularity/fastembedr_cuda.sif
sha256sum -c "$root/image.sha256"
sha256sum -c "$root/source.sha256"
export REAL_COMMON_R=$base/benchmark_scripts/fastembedr_jss_review_validation/common/common.R
singularity exec "$image" /opt/r46/bin/Rscript \
    "$suite/prepare.R" "$base/Data" "$dataset" "$root/$dataset/input"
test -s "$root/$dataset/input/input_manifest.csv"
stat -Lc '%d:%i:%s:%Y:%Z' "$root/$dataset/input/input.f32" \
    > "$root/$dataset/input/input.stat"
