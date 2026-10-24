#!/bin/bash
#SBATCH --job-name=feR_cpu32
#SBATCH --partition=ada
#SBATCH --cpus-per-task=32
#SBATCH --mem=12G
#SBATCH --time=01:30:00
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_cpu32_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_cpu32_%j.err

set -euo pipefail
method=${1:?Provide pca, tsne, or umap}
root=${2:?Provide new result directory}
suite=/scratch/firenze/NN/benchmark_scripts_cpu32_20261024
image=/scratch/firenze/NN/singularity/\
fastembedr_cuda.candidate_20261016_matrix.sif
expected_image=91387e35888bdd61fbd75bff7add5cf4fca7b3b4bdc15522ab3eade78ea8ea2e
test "${SLURM_JOB_PARTITION:-}" = ada
test "${SLURM_GPUS:-0}" = 0
case "$method" in pca|tsne|umap) ;; *) exit 2 ;; esac
test ! -e "$root"
mkdir -p "$root/library"
printf '%s  %s\n' "$expected_image" "$image" | sha256sum -c -
sha256sum -c "$suite/SHA256SUMS"
sha256sum "$suite/fastEmbedR_0.1.tar.gz" \
    "$suite/profile_cpu32.R" "$image" > "$root/source.sha256"
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
singularity exec "$image" env FASTEMBEDR_USE_CUDA=0 \
    FASTEMBEDR_REQUIRE_CUDA=0 FASTEMBEDR_USE_CUVS=0 \
    FASTEMBEDR_USE_RAFT=0 FASTEMBEDR_USE_METAL=0 \
    /opt/r46/bin/R CMD INSTALL --library="$root/library" \
    "$suite/fastEmbedR_0.1.tar.gz" \
    > "$root/install.out" 2> "$root/install.err"
sha256sum "$root/library/fastEmbedR/libs/fastEmbedR.so" \
    > "$root/native_so.sha256"
for spec in 8_a 16_a 32_a 32_b 16_b 8_b; do
    cores=${spec%%_*}
    case_root="$root/${method}_${spec}"
    mkdir -p "$case_root"
    /usr/bin/time -v -o "$case_root/time.txt" \
        singularity exec "$image" env R_LIBS_USER="$root/library" \
        /opt/r46/bin/Rscript "$suite/profile_cpu32.R" \
        "$method" "$cores" "$root/library" "$case_root" \
        > "$case_root/stdout.txt" 2> "$case_root/stderr.txt"
done
if [[ "$method" = umap ]]; then
    case_root="$root/umap_1_a"
    mkdir -p "$case_root"
    /usr/bin/time -v -o "$case_root/time.txt" \
        singularity exec "$image" env R_LIBS_USER="$root/library" \
        /opt/r46/bin/Rscript "$suite/profile_cpu32.R" \
        umap 1 "$root/library" "$case_root" \
        > "$case_root/stdout.txt" 2> "$case_root/stderr.txt"
fi
