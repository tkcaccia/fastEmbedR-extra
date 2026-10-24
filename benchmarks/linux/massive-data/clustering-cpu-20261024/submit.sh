#!/usr/bin/env bash
set -euo pipefail
root=/scratch/firenze/NN
suite=$root/benchmark_scripts/massive-data/clustering-cpu-20261024
image=${CLUSTER_IMAGE:?Set source-locked candidate SIF path}
expected=${CLUSTER_IMAGE_SHA256:?Set candidate SIF SHA256}
test -z "${CUDA_VISIBLE_DEVICES:-}"
test -s "$suite/run.R"
test -s "$suite/worker.sbatch"
export CLUSTER_RESUME=${CLUSTER_RESUME:-0}
if [[ "$CLUSTER_RESUME" != 0 && "$CLUSTER_RESUME" != 1 ]]; then
    echo 'CLUSTER_RESUME must be 0 or 1.' >&2
    exit 1
fi
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
quota -s
free=$(quota -s | awk '/hpc-scratch/{getline; print $2-$1}')
if [[ ! "$free" =~ ^[0-9]+$ ]] || ((free < 100)); then
    echo 'Need at least 100 GiB verified scratch quota.' >&2
    exit 1
fi
if [[ ${1:-} = --plan ]]; then
    printf '%s\n' '1M graph build: ada, 32 CPU, 24h' \
        '1M matched resident/file fits: ada, graph dependency only' \
        '1M classic matrix fit: ada, independent' \
        '1M landmark fit and 1/8/16/32-CPU vote profiles' \
        '100M landmark Leiden: ada, 32 CPU, after 1M pilot, checkpointed'
    exit 0
fi
test $# -eq 0
campaign=$root/fastEmbedR-results/massive-data/clustering-cpu/\
$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$campaign"
printf '%s\n' "$expected" > "$campaign/image.sha256"
printf 'stage\tjob_id\n' > "$campaign/jobs.tsv"
submit() {
    local stage=$1 cores=$2 memory=$3 time=$4 dependency=$5
    local mode=$6 method=$7 job
    local flags=(--parsable --partition=ada --cpus-per-task="$cores"
        --mem="$memory" --time="$time")
    if [[ -n "$dependency" ]]; then
        flags+=(--dependency="afterok:$dependency")
    fi
    job=$(sbatch "${flags[@]}" "$suite/worker.sbatch" \
        "$mode" "$method" "$campaign" "$image" "$expected")
    printf '%s\t%s\n' "$stage" "$job" >> "$campaign/jobs.tsv"
    printf '%s %s\n' "$stage" "$job"
}
build=$(submit build 32 24G 24:00:00 '' build leiden | tail -n 1)
build_id=${build##* }
submit classic_leiden 32 96G 24:00:00 '' classic leiden
landmark=$(submit landmark1m 32 16G 24:00:00 '' \
    landmark1m leiden | tail -n 1)
landmark_id=${landmark##* }
submit landmark100m 32 32G 72:00:00 "$landmark_id" \
    landmark100m leiden
for cores in 1 8 16 32; do
    submit "vote${cores}" "$cores" 12G 04:00:00 \
        "$landmark_id" "vote${cores}" leiden
done
for method in leiden louvain; do
    submit "resident_$method" 8 96G 12:00:00 "$build_id" \
        resident "$method"
    submit "file_$method" 1 16G 12:00:00 "$build_id" \
        file "$method"
done
printf 'Campaign: %s\n' "$campaign"
