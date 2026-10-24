#!/usr/bin/env bash
set -euo pipefail
root=/scratch/firenze/NN
suite=$root/benchmark_scripts/massive-data/clustering-cpu-20261024
image=$root/singularity/fastembedr_cpu_cluster_20261024.sif
expected=5ce92891f6543169078977be5f995fb475d5825c16eee3d035f5829083b6953b
test -z "${CUDA_VISIBLE_DEVICES:-}"
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
test -s "$suite/run_scale10m.R"
test -s "$suite/scale10m.sbatch"
campaign=$root/fastEmbedR-results/massive-data/clustering-cpu-scale10m/\
$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$campaign"
printf 'cores\tjob_id\n' > "$campaign/jobs.tsv"
for cores in 1 4 8 16 32; do
    output=$campaign/cpu$cores
    job=$(sbatch --parsable --partition=ada \
        --cpus-per-task="$cores" --mem=16G --time=02:00:00 \
        "$suite/scale10m.sbatch" "$cores" "$output" \
        "$image" "$expected")
    printf '%s\t%s\n' "$cores" "$job" >> "$campaign/jobs.tsv"
done
printf 'Campaign: %s\n' "$campaign"
cat "$campaign/jobs.tsv"
