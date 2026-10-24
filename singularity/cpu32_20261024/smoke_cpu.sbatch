#!/usr/bin/env bash
#SBATCH --job-name=feR_cpu32_smoke
#SBATCH --partition=ada
#SBATCH --cpus-per-task=32
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_cpu32_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_cpu32_%j.err
set -euo pipefail
image=${FASTEMBEDR_CPU32_IMAGE:?Set source-locked candidate SIF path}
expected=${FASTEMBEDR_CPU32_IMAGE_SHA256:?Set candidate SHA256}
root=${FASTEMBEDR_CPU32_ROOT:?Set private output directory}
script=${FASTEMBEDR_CPU32_SCRIPT:?Set smoke script path}
test -s "$image"
test -s "$script"
mkdir -p "$root"
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
singularity exec --cleanenv \
    --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
    /opt/r46/bin/Rscript "$script" "$root"
