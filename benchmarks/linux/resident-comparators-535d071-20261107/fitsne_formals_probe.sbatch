#!/bin/bash
#SBATCH --job-name=fer-fitsne-api-probe
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/fitsne-api-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/fitsne-api-%j.err
set -Eeuo pipefail
image=/scratch/firenze/NN/singularity/release_535d071_20261107/fastembedr_535d071_20261107.sif
test -f "$image"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
singularity exec "$image" /opt/r46/bin/Rscript -e '
  env <- new.env(parent = globalenv())
  sys.source("/opt/fit-sne/bin/fast_tsne.R", envir = env, chdir = TRUE)
  stopifnot(exists("fftRtsne", envir = env, inherits = FALSE))
  print(names(formals(get("fftRtsne", envir = env, inherits = FALSE))))
'
