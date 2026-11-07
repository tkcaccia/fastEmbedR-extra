#!/bin/bash
#SBATCH --job-name=fer-py-bridge-probe
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=3G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/bridge-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/bridge-%j.err
set -Eeuo pipefail
image=/scratch/firenze/NN/singularity/release_535d071_20261107/fastembedr_535d071_20261107.sif
test -f "$image"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
export RETICULATE_PYTHON=/opt/conda/bin/python
singularity exec "$image" /opt/r46/bin/Rscript -e '
  stopifnot(requireNamespace("reticulate", quietly = TRUE))
  reticulate::use_python("/opt/conda/bin/python", required = TRUE)
  np <- reticulate::import("numpy", convert = FALSE)
  tsne <- reticulate::import("openTSNE", convert = FALSE)
  umap <- reticulate::import("umap", convert = FALSE)
  stopifnot(!is.null(np), !is.null(tsne), !is.null(umap))
  cat("R_PYTHON_BRIDGE_PASS ", reticulate::py_config()$python, "\n", sep = "")
'
