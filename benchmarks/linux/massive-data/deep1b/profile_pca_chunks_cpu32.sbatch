#!/bin/bash
#SBATCH --job-name=feR_pca_chunks
#SBATCH --partition=ada
#SBATCH --cpus-per-task=32
#SBATCH --mem=6G
#SBATCH --time=00:30:00
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_pca_chunks_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_pca_chunks_%j.err

set -euo pipefail
root=${1:?Provide a new result directory}
suite=/scratch/firenze/NN/benchmark_scripts_cpu32_20261024
library=/scratch/firenze/NN/fastEmbedR-results/massive-data/\
cpu32_20261024/pca/library
image=/scratch/firenze/NN/singularity/\
fastembedr_cuda.candidate_20261016_matrix.sif
test "${SLURM_JOB_PARTITION:-}" = ada
test "${SLURM_GPUS:-0}" = 0
test ! -e "$root"
mkdir -p "$root"
printf '%s  %s\n' \
    eeeba1dac18960c996297f04d75a36142638969dfc764d3c456345a05f2ec79e \
    "$library/fastEmbedR/libs/fastEmbedR.so" | sha256sum -c -
printf '%s  %s\n' \
    91387e35888bdd61fbd75bff7add5cf4fca7b3b4bdc15522ab3eade78ea8ea2e \
    "$image" | sha256sum -c -
printf '%s  %s\n' \
    fea7815d04bde141a0a4626d79d133ce1a709cf459e1dfafb34f743f553454a7 \
    "$suite/profile_pca_chunks_cpu32.R" | sha256sum -c -
sha256sum "$suite/profile_pca_chunks_cpu32.R" > "$root/source.sha256"
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
for spec in 16_100000 32_100000 32_500000 16_500000 \
    16_1000000 32_1000000; do
    IFS=_ read -r cores chunk <<< "$spec"
    case_root="$root/$spec"
    mkdir -p "$case_root"
    /usr/bin/time -v -o "$case_root/time.txt" \
        singularity exec "$image" env R_LIBS_USER="$library" \
        /opt/r46/bin/Rscript "$suite/profile_pca_chunks_cpu32.R" \
        "$cores" "$chunk" "$library" "$case_root" \
        > "$case_root/stdout.txt" 2> "$case_root/stderr.txt"
done
