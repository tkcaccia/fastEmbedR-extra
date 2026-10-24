#!/usr/bin/env bash
#SBATCH --partition=ada
#SBATCH --job-name=feR_cluster_scale10m
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_cluster_scale_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_cluster_scale_%j.err
set -euo pipefail
cores=${1:?}
output=${2:?}
image=${3:?}
expected=${4:?}
suite=/scratch/firenze/NN/benchmark_scripts/massive-data/clustering-cpu-20261024
test "${SLURM_JOB_PARTITION:-}" = ada
test "${SLURM_GPUS:-0}" = 0
test -z "${CUDA_VISIBLE_DEVICES:-}"
test "${SLURM_CPUS_PER_TASK:-0}" = "$cores"
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
mkdir -p "$output"
sha256sum "$suite/run_scale10m.R" "$image" > "$output/source.sha256"
stat -c '%n %s %Y' \
    /scratch/firenze/NN/Data/BigANN/deep/1000000000/base.1000000000.fbin \
    > "$output/input.stat"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
/usr/bin/time -v -o "$output/time.txt" \
    singularity exec "$image" env FASTEMBEDR_USE_CUDA=0 \
    FASTEMBEDR_REQUIRE_CUDA=0 FASTEMBEDR_USE_CUVS=0 \
    FASTEMBEDR_USE_RAFT=0 FASTEMBEDR_USE_METAL=0 \
    /opt/r46/bin/Rscript "$suite/run_scale10m.R" "$cores" "$output" \
    > "$output/stdout.txt" 2> "$output/stderr.txt"
test -s "$output/metrics.csv"
du -sb "$output" | cut -f1 > "$output/final_workspace_bytes.txt"
