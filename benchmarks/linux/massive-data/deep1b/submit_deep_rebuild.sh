#!/usr/bin/env bash
set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
expected=${DEEP1B_IMAGE_SHA256:-}
if [[ -z "$expected" ]]; then
    expected=0925105c3113c60225de70f948ad059dbcbd60ce3c4bccdd6286a366ab3131d8
fi
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
export DEEP1B_IMAGE_SHA256="$expected"
if squeue -h -u "$USER" -o '%j' | grep '^feR_fg_' >/dev/null; then
    echo "An existing full-graph campaign is still queued or running." >&2
    exit 2
fi
ledger=$base/fastEmbedR-results/massive-data/rebuild/
ledger+=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$ledger"
printf 'mode\trows\tbackend\tdependency\tjob\tcampaign\n' \
    > "$ledger/jobs.tsv"
submit() {
    local mode=$1 rows=$2 backend=$3 after=${4:-}
    local dependency_type=${5:-afterok}
    local output record job campaign
    output=$(DEEP1B_FIT_MODE="$mode" DEEP1B_FULLGRAPH_ROWS="$rows" \
        DEEP1B_BACKEND_FILTER="$backend" DEEP1B_AFTER_JOB="$after" \
        DEEP1B_DEPENDENCY_TYPE="$dependency_type" \
        bash "$suite/submit_fullgraph5m.sh" deep)
    record=$(printf '%s\n' "$output" | awk -F '\t' \
        '$1 == "deep" && $2 == "'"$backend"'" {print}')
    [[ -n "$record" ]] || { echo "$output" >&2; exit 1; }
    job=$(printf '%s\n' "$record" | cut -f 5)
    campaign=$(printf '%s\n' "$record" | cut -f 6)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$mode" "$rows" "$backend" "${after:--}" "$job" \
        "$campaign" >> "$ledger/jobs.tsv"
    printf '%s\n' "$job"
}
submit classic 1000000 cpu >/dev/null
submit classic 1000000 cuda >/dev/null
submit full 1000000 cpu >/dev/null
submit full 1000000 cuda >/dev/null
submit pca 10000000 cpu >/dev/null
submit pca 10000000 cuda >/dev/null
submit pca 100000000 cpu >/dev/null
submit pca 100000000 cuda >/dev/null
full_cpu_10m=$(submit full 10000000 cpu)
full_cuda_10m=$(submit full 10000000 cuda)

# The 100M graph-sort workspaces must not overlap on scratch.
after=
if [[ "$full_cpu_10m" != BLOCKED ]]; then after=$full_cpu_10m; fi
cpu_umap=$(submit full_umap 100000000 cpu "$after" afterany)
after=
if [[ "$cpu_umap" != BLOCKED ]]; then after=$cpu_umap; fi
cpu_tsne=$(submit full_tsne 100000000 cpu "$after" afterany)
after=
if [[ "$cpu_tsne" != BLOCKED ]]; then after=$cpu_tsne; fi
if [[ "$full_cuda_10m" != BLOCKED ]]; then
    if [[ -n "$after" ]]; then after+=:; fi
    after+=$full_cuda_10m
fi
cuda_umap=$(submit full_umap 100000000 cuda "$after" afterany)
after=
if [[ "$cuda_umap" != BLOCKED ]]; then after=$cuda_umap; fi
submit full_tsne 100000000 cuda "$after" afterany >/dev/null
printf 'Ledger: %s/jobs.tsv\n' "$ledger"
