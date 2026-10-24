#!/usr/bin/env bash
#SBATCH --job-name=feR_cpu32_profile
#SBATCH --partition=ada
#SBATCH --cpus-per-task=32
#SBATCH --mem=12G
#SBATCH --time=01:30:00
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_cpu32_profile_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_cpu32_profile_%j.err
set -euo pipefail
method=${1:?Provide pca, tsne, or umap}
root=${2:?Provide new output directory}
case "$method" in pca|tsne|umap) ;; *) exit 2 ;; esac
test "${SLURM_JOB_PARTITION:-}" = ada
test "${SLURM_GPUS:-0}" = 0
test ! -e "$root"
mkdir -p "$root"
base=/scratch/firenze/NN
image=$base/singularity/fastembedr_cpu32.candidate_20261024.sif
script=$base/benchmark_scripts/cpu32_20261024/profile_cpu32.R
expected=dd9ed112c638b53f06d7baed51a17de515fa7d58d730c8352fa6fd732ffd265a
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
sha256sum "$image" "$script" > "$root/source.sha256"
/usr/bin/time -v -o "$root/time.txt" \
    singularity exec --cleanenv \
    --bind "$base:$base" "$image" \
    env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    /opt/r46/bin/Rscript "$script" "$method" 32 \
    /opt/r46/lib/R/library "$root" \
    > "$root/stdout.txt" 2> "$root/stderr.txt"
test -s "$root/metrics.csv"
