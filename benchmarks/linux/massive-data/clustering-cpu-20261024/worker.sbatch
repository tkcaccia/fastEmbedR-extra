#!/usr/bin/env bash
#SBATCH --job-name=feR_cluster_cpu
#SBATCH --partition=ada
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_cluster_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_cluster_%j.err
set -euo pipefail
mode=${1:?}
method=${2:?}
campaign=${3:?}
image=${4:?}
expected=${5:?}
suite=/scratch/firenze/NN/benchmark_scripts/massive-data/clustering-cpu-20261024
input=/scratch/firenze/NN/Data/BigANN/deep/1000000000/base.1000000000.fbin
test "${SLURM_JOB_PARTITION:-}" = ada
test "${SLURM_GPUS:-0}" = 0
test -z "${CUDA_VISIBLE_DEVICES:-}"
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
test -s "$input"
case "$mode" in
    build) out="$campaign/build" ;;
    *) out="$campaign/${mode}_${method}" ;;
esac
mkdir -p "$out"
target=$out
if [[ "$mode" = build ]]; then
    target=$campaign/graph
    mkdir -p "$target"
fi
printf 'utc\tworkspace_bytes\n' > "$out/disk_samples.tsv"
(
    while :; do
        printf '%s\t%s\n' "$(date -u +%FT%TZ)" \
            "$(du -sb "$target" | cut -f1)" \
            >> "$out/disk_samples.tsv"
        sleep 60
    done
) &
monitor=$!
trap 'kill "$monitor" 2>/dev/null || true' EXIT
sha256sum "$image" "$suite/run.R" > "$out/source.sha256"
stat -c '%n %s %Y' "$input" > "$out/input.stat"
printf '%s\n' \
    'Deep1B manifest SHA256: 1178bb266619c2d7882795861772b50cb0e2bf111a3b786a188aa3ea6137c7c4' \
    > "$out/input_manifest.txt"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
/usr/bin/time -v -o "$out/time.txt" \
    singularity exec "$image" env FASTEMBEDR_USE_CUDA=0 \
    FASTEMBEDR_REQUIRE_CUDA=0 FASTEMBEDR_USE_CUVS=0 \
    FASTEMBEDR_USE_RAFT=0 FASTEMBEDR_USE_METAL=0 \
    /opt/r46/bin/Rscript "$suite/run.R" "$mode" "$method" \
    "$input" "$campaign" "$out" \
    > "$out/stdout.txt" 2> "$out/stderr.txt"
test -s "$out/metrics.csv"
printf '%s\t%s\n' "$(date -u +%FT%TZ)" \
    "$(du -sb "$target" | cut -f1)" >> "$out/disk_samples.tsv"
awk 'NR > 1 && $2 > peak {peak=$2} END {print peak+0}' \
    "$out/disk_samples.tsv" > "$out/workspace_peak_bytes.txt"
