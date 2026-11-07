#!/bin/bash
#SBATCH --job-name=fer-pca-image-535d071
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=32
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --output=/scratch/firenze/NN/singularity/release_535d071_20261107/cpu-pilot-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_535d071_20261107/cpu-pilot-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/singularity/release_535d071_20261107
image="$root/fastembedr_535d071_20261107.sif"
expected=15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
[[ $(sha256sum "$image" | cut -d' ' -f1) == "$expected" ]]
printf 'host=%s job=%s image_sha256=%s\n' \
    "$(hostname)" "$SLURM_JOB_ID" "$expected"
singularity exec --cleanenv "$image" /opt/r46/bin/Rscript \
    "$root/cpu_pca_pilot.R"
