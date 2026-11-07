#!/bin/bash
#SBATCH --job-name=fer-cuda-source-install
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=00:30:00
#SBATCH --output=/scratch/firenze/NN/singularity/candidate_dd657a8_20261107/install-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/candidate_dd657a8_20261107/install-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/singularity/candidate_dd657a8_20261107
image=/scratch/firenze/NN/singularity/release_535d071_20261107/fastembedr_535d071_20261107.sif
archive="$root/fer_stream_dd657a8.tar.gz"
test -f "$image"
test -f "$archive"
[[ $(sha256sum "$image" | cut -d' ' -f1) == \
  15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2 ]]
[[ $(sha256sum "$archive" | cut -d' ' -f1) == \
  0d6446a1404c6f35ee2c33a8fb5b9ead1fd9357be3766e693df71ce9bafe31e6 ]]
test ! -e "$root/source"
test ! -e "$root/library"
mkdir "$root/source" "$root/library"
tar -xzf "$archive" -C "$root/source"
singularity exec --cleanenv --bind /scratch/firenze/NN:/scratch/firenze/NN \
  "$image" /usr/bin/env MAKEFLAGS=-j4 /opt/r46/bin/R CMD INSTALL \
  --library="$root/library" "$root/source/fastEmbedR"
worker="$root/library/fastEmbedR/python/massive_cuda_stream_cluster.py"
[[ $(sha256sum "$worker" | cut -d' ' -f1) == \
  deaa1ab627ad24fc20b17ce897ba32ef868e679c23ab39365add7d7ee5d16c4c ]]
singularity exec --cleanenv --bind /scratch/firenze/NN:/scratch/firenze/NN \
  "$image" /opt/r46/bin/Rscript -e \
  '.libPaths(c(commandArgs(TRUE)[[1L]], .libPaths())); library(fastEmbedR); stopifnot("graph_cluster" %in% getNamespaceExports("fastEmbedR")); cat("candidate_install_load_pass\n")' \
  "$root/library"
printf 'installed_candidate=dd657a8 image=535d071 host=%s job=%s\n' \
  "$(hostname)" "$SLURM_JOB_ID"
