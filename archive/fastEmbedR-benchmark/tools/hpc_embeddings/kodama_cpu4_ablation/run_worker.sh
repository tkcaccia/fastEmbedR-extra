#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE:?IMAGE is required}"
: "${SCRIPT:?SCRIPT is required}"

export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export RCPP_PARALLEL_NUM_THREADS=4

exec apptainer exec --cleanenv \
  --env OMP_NUM_THREADS=4,OPENBLAS_NUM_THREADS=1,MKL_NUM_THREADS=1,VECLIB_MAXIMUM_THREADS=1,NUMEXPR_NUM_THREADS=1,RCPP_PARALLEL_NUM_THREADS=4 \
  --bind /scratch/firenze/NN:/scratch/firenze/NN \
  "${IMAGE}" Rscript "${SCRIPT}" "$@"
