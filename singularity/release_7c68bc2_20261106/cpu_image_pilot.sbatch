#!/bin/bash
#SBATCH --job-name=fer-cpu-image-7c68bc2
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/singularity/release_7c68bc2_20261106/cpu-pilot-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_7c68bc2_20261106/cpu-pilot-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/singularity/release_7c68bc2_20261106
image="$root/fastembedr_7c68bc2_20261106.sif"
[[ -r "$image" && -r "$root/cpu_image_pilot.R" ]]
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
singularity exec --cleanenv "$image" /opt/r46/bin/Rscript \
    "$root/cpu_image_pilot.R"
