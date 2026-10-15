#!/usr/bin/env bash
# Submit independent Deep1B jobs, capped at 20 million fitted rows.
set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
expected=${DEEP1B_IMAGE_SHA256:-}
rebuild_knn=${DEEP1B_REBUILD_KNN_FOR_UMAP:-0}
[[ "$rebuild_knn" == 0 || "$rebuild_knn" == 1 ]] || {
    echo 'DEEP1B_REBUILD_KNN_FOR_UMAP must be 0 or 1.' >&2
    exit 2
}
if [[ -z "$expected" ]]; then
    expected=0925105c3113c60225de70f948ad059dbcbd60ce3c4bccdd6286a366ab3131d8
fi
plan=$(mktemp)
trap 'rm -f "$plan"' EXIT
printf 'mode\trows\tbackend\tcpu_cores\tgpu_devices\trequired_bytes\n' \
    > "$plan"
add_case() {
    local mode=$1 rows=$2 backend=$3 cores=$4 devices=$5
    local required
    if [[ "$mode" == full ]]; then
        if [[ "$rebuild_knn" == 1 ]]; then
            required=$((1112 * rows + 8))
        else
            required=$((1352 * rows + 8))
        fi
    elif [[ "$mode" == classic ]]; then
        required=$((1152 * rows))
    else
        required=$((24 * rows))
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$mode" "$rows" "$backend" "$cores" \
        "${devices:--}" "$required" >> "$plan"
}

add_case classic 1000000 cpu 4 -
add_case classic 1000000 cuda 1 0
for rows in 1000000 10000000 20000000; do
    for cores in 1 4 8; do
        add_case full "$rows" cpu "$cores" -
    done
    add_case full "$rows" cuda 1 0
    add_case full "$rows" cuda 1 0,1
done
add_case pca 20000000 cuda 1 0,1

if [[ "${1:-}" == --plan ]]; then
    cat "$plan"
    exit 0
fi
[[ $# == 0 ]] || { echo 'Usage: submit_20m.sh [--plan]' >&2; exit 2; }
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
if squeue -h -u "$USER" -o '%j' | grep '^feR_fg_' >/dev/null; then
    echo 'An earlier full-graph campaign is still active.' >&2
    exit 2
fi
quota_free=${DEEP1B_QUOTA_FREE_BYTES:-}
if [[ -z "$quota_free" ]] && command -v myquota >/dev/null; then
    quota_free=$(myquota | awk '$1 == "/scratch" {
        gsub(/GB/, "", $2); gsub(/GB/, "", $3)
        printf "%.0f", ($2 - $3) * 1000000000
    }')
fi
[[ "$quota_free" =~ ^[0-9]+$ ]] || {
    echo 'Set DEEP1B_QUOTA_FREE_BYTES from myquota.' >&2
    exit 2
}
required=$(awk -F '\t' 'NR > 1 {sum += $6}
    END {printf "%.0f", sum}' "$plan")
if ((required * 5 > quota_free * 4)); then
    printf 'Need >= %s free quota bytes for independent cases; have %s.\n' \
        "$(( (required * 5 + 3) / 4 ))" "$quota_free" >&2
    exit 3
fi
python3 "$suite/validate_input.py" \
    "$base/Data/BigANN/deep/1000000000/base.1000000000.fbin" \
    --dataset deep >/dev/null
export DEEP1B_BASE="$base" DEEP1B_IMAGE="$image"
export DEEP1B_IMAGE_SHA256="$expected"
export DEEP1B_REBUILD_KNN_FOR_UMAP="$rebuild_knn"
export DEEP1B_QUOTA_FREE_BYTES="$quota_free"
export DEEP1B_FIRST_ROW=1000001 DEEP1B_SMOKE=0
ledger=$base/fastEmbedR-results/massive-data/rebuild20m/
ledger+=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$ledger"
printf 'Writing job ledger: %s/jobs.tsv\n' "$ledger"
cp "$plan" "$ledger/plan.tsv"
printf 'mode\trows\tbackend\tcpu_cores\tgpu_devices\tjob\tcampaign\n' \
    > "$ledger/jobs.tsv"
{
    printf 'route\tstatus\treason\n'
    printf 'classic_cuda_2gpu\tUNSUPPORTED\t%s\n' \
        'The in-memory APIs have no multi-GPU execution path.'
    printf 'fullgraph_cuda_2gpu\tSCHEDULED\t%s\n' \
        'KNN, UMAP and t-SNE receive the same two-device request.'
    printf 'umap_optimizer_cpu_4_or_8\tUNSUPPORTED\t%s\n' \
        'Only graph preparation uses the requested CPU workers.'
    printf 'leiden_optimizer_cpu_4_or_8\tUNSUPPORTED\t%s\n' \
        'The full-graph clustering optimizer requires one worker.'
    printf 'input_larger_than_l40s_vram\tNOT_TESTED\t%s\n' \
        'Twenty million Deep1B float32 rows occupy only 7.68 GB.'
} > "$ledger/unsupported_routes.tsv"
while IFS=$'\t' read -r mode rows backend cores devices bytes; do
    [[ "$mode" != mode ]] || continue
    [[ "$devices" != - ]] || devices=
    output=$(DEEP1B_FIT_MODE="$mode" \
        DEEP1B_FULLGRAPH_ROWS="$rows" \
        DEEP1B_BACKEND_FILTER="$backend" \
        DEEP1B_CPU_CORES="$cores" \
        DEEP1B_GPU_DEVICES="$devices" \
        DEEP1B_AFTER_JOB= \
        bash "$suite/submit_fullgraph5m.sh" deep)
    record=$(printf '%s\n' "$output" | awk -F '\t' \
        -v backend="$backend" '$1 == "deep" && $2 == backend')
    [[ -n "$record" ]] || { echo "$output" >&2; exit 1; }
    job=$(printf '%s\n' "$record" | cut -f 5)
    campaign=$(printf '%s\n' "$record" | cut -f 6)
    [[ "$job" != BLOCKED ]] || {
        echo "Preflight blocked $mode $rows $backend $cores." >&2
        exit 3
    }
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$mode" "$rows" "$backend" "$cores" \
        "${devices:--}" "$job" "$campaign" \
        >> "$ledger/jobs.tsv"
done < "$plan"
printf 'Ledger: %s/jobs.tsv\n' "$ledger"
