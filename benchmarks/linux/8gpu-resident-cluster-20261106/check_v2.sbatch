#!/bin/bash
#SBATCH --job-name=fer-8gpu-cpucheck-v2
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/fastembedr_8gpu_cpucheck_20261106/check-v2-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/fastembedr_8gpu_cpucheck_20261106/check-v2-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/fastembedr_8gpu_cpucheck_20261106
image=/scratch/firenze/NN/singularity/release_afeaffc_20261106/fastembedr_afeaffc_20261106.sif
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
[[ -f "$root/library/fastEmbedR/R/fastEmbedR" ]]
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
    /opt/r46/bin/Rscript "$root/check_v2.R"
