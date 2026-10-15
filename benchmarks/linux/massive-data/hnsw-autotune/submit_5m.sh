#!/usr/bin/env bash
# Submit a bounded 5M-row CPU HNSW screen; never starts a full graph.
set -euo pipefail

mode=${1:-screen}
[[ $# -le 1 ]] && [[ "$mode" == screen || "$mode" == refine ]] || {
    echo "Usage: submit_5m.sh [screen|refine]" >&2
    exit 2
}
if [[ "$mode" == screen ]]; then
    generator=make_cases_5m.py
    audit_phase=audit_5m
    suffix=fresh5m
else
    generator=make_cases_refine.py
    audit_phase=audit_refine
    suffix=refine5m
fi

base=${HNSW_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/hnsw-autotune
image=${HNSW_IMAGE:-$base/singularity/fastembedr_cuda.sif}
data_root=${BIGANN_DATA_ROOT:-$base/Data/BigANN}
parent=$base/fastEmbedR-results/massive-data/hnsw-autotune
account=${HNSW_ACCOUNT:-immunology}
partition=${HNSW_PARTITION:-ada}
test -s "$image" || { echo "Missing image: $image" >&2; exit 1; }
active=$(squeue -h -u "$USER" -o '%j')
if printf '%s\n' "$active" | grep -Eq '^feR_hnsw_'; then
    echo "An HNSW calibration campaign is already active." >&2
    exit 1
fi
files=()
for file in make_cases.py make_cases_5m.py make_cases_refine.py \
    worker.R worker.sbatch preflight_5m.R audit.py audit_5m.py \
    audit_refine.py submit_5m.sh; do
    test -s "$suite/$file" || {
        echo "Missing suite file: $suite/$file" >&2
        exit 1
    }
    files+=("$suite/$file")
done
mkdir -p "$parent" "$base/benchmark_logs"
root=$parent/$(date -u +%Y%m%dT%H%M%SZ)_${suffix}_$RANDOM
python3 "$suite/$generator" "$root" "$data_root"
touch "$root/preflight.required"
sha256sum "$image" "${files[@]}" > "$root/source.sha256"
sha256sum "${files[@]}" > "$root/code.sha256"
printf 'stage\tjob_id\tcase_count\n' > "$root/jobs.tsv"
common=(--parsable --account="$account" --partition="$partition"
    --chdir="$base" --output="$base/benchmark_logs/feR_hnsw_%A_%a.out"
    --error="$base/benchmark_logs/feR_hnsw_%A_%a.err")
exports="ALL,HNSW_SUITE=$suite,HNSW_ROOT=$root,HNSW_IMAGE=$image"
exports+=",BIGANN_DATA_ROOT=$data_root"
preflight=$(sbatch "${common[@]}" --job-name=feR_hnsw_preflight \
    --cpus-per-task=1 --mem=2G --time=00:20:00 \
    --export="$exports,HNSW_PHASE=preflight_5m" "$suite/worker.sbatch")
printf 'preflight\t%s\t1\n' "$preflight" >> "$root/jobs.tsv"
for item in deep:0:0-1:2 turing:1:2:1; do
    IFS=: read -r dataset truth_task sweep_tasks sweep_count <<< "$item"
    truth=$(sbatch "${common[@]}" --job-name=feR_hnsw_truth \
        --dependency="afterany:$preflight" --array="$truth_task" \
        --cpus-per-task=8 --mem=24G --time=12:00:00 \
        --export="$exports,HNSW_PHASE=truth" "$suite/worker.sbatch")
    printf '%s_truth\t%s\t1\n' "$dataset" "$truth" \
        >> "$root/jobs.tsv"
    sweep=$(sbatch "${common[@]}" --job-name=feR_hnsw_sweep \
        --dependency="afterany:$truth" --array="$sweep_tasks" \
        --cpus-per-task=4 --mem=24G --time=12:00:00 \
        --export="$exports,HNSW_PHASE=sweep" "$suite/worker.sbatch")
    printf '%s_sweep\t%s\t%s\n' "$dataset" "$sweep" \
        "$sweep_count" >> "$root/jobs.tsv"
    if [[ "$dataset" == deep ]]; then
        deep_sweep=$sweep
    else
        turing_sweep=$sweep
    fi
done
audit=$(sbatch "${common[@]}" --job-name=feR_hnsw_audit \
    --dependency="afterany:$deep_sweep:$turing_sweep" \
    --cpus-per-task=1 --mem=4G --time=00:30:00 \
    --export="$exports,HNSW_PHASE=$audit_phase" "$suite/worker.sbatch")
printf 'audit\t%s\t1\n' "$audit" >> "$root/jobs.tsv"
printf 'Campaign: %s\nAudit job: %s\n' "$root" "$audit"
cat "$root/jobs.tsv"
