#!/bin/bash
#SBATCH --job-name=feR_pca_phases
#SBATCH --partition=ada
#SBATCH --cpus-per-task=32
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_pca_phases_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_pca_phases_%j.err

set -euo pipefail
root=${1:?Provide a new result directory}
suite=/scratch/firenze/NN/benchmark_scripts_cpu32_20261024
library=/scratch/firenze/NN/fastEmbedR-results/massive-data/\
cpu32_20261024/pca/library
image=/scratch/firenze/NN/singularity/\
fastembedr_cuda.candidate_20261016_matrix.sif
test "${SLURM_JOB_PARTITION:-}" = ada
test "${SLURM_GPUS:-0}" = 0
printf '%s  %s\n' \
    91387e35888bdd61fbd75bff7add5cf4fca7b3b4bdc15522ab3eade78ea8ea2e \
    "$image" | sha256sum -c -
printf '%s  %s\n' \
    bf41e728486de9fa0274eb9c1960c77769ed3360e1d91e29f81ac7558cf8922a \
    "$suite/profile_pca_phases_cpu32.R" | sha256sum -c -
test ! -e "$root"
mkdir -p "$root"
printf '%s  %s\n' \
    eeeba1dac18960c996297f04d75a36142638969dfc764d3c456345a05f2ec79e \
    "$library/fastEmbedR/libs/fastEmbedR.so" | sha256sum -c -
sha256sum "$suite/profile_pca_phases_cpu32.R" "$image" \
    > "$root/source.sha256"
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
for spec in 8_a 16_a 32_a 32_b 16_b 8_b; do
    cores=${spec%%_*}
    case_root="$root/$spec"
    mkdir -p "$case_root"
    /usr/bin/time -v -o "$case_root/time.txt" \
        singularity exec "$image" env R_LIBS_USER="$library" \
        /opt/r46/bin/Rscript "$suite/profile_pca_phases_cpu32.R" \
        "$cores" "$library" "$case_root" \
        > "$case_root/stdout.txt" 2> "$case_root/stderr.txt"
done
