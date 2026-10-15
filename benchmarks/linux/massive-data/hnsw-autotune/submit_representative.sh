#!/usr/bin/env bash
# One source-locked calibration with parallel dataset/window branches.
set -euo pipefail

[[ $# -eq 0 ]] || { echo 'Usage: submit_representative.sh' >&2; exit 2; }
base=${HNSW_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/hnsw-autotune
image=${HNSW_IMAGE:-$base/singularity/fastembedr_cuda.sif}
data_root=${BIGANN_DATA_ROOT:-$base/Data/BigANN}
account=${HNSW_ACCOUNT:-immunology}
partition=${HNSW_PARTITION:-ada}
parent=$base/fastEmbedR-results/massive-data/hnsw-autotune
files=(make_cases.py make_cases_representative.py worker.R
    worker.sbatch preflight_5m.R audit.py audit_5m.py
    audit_representative.py followup_after_representative.py
    full_graph_gate.py followup.sbatch submit_representative.sh)
for file in "${files[@]}"; do test -s "$suite/$file"; done
for part in deep1b visualization; do
    test -d "$base/benchmark_scripts/massive-data/$part"
done
test -s "$base/benchmark_scripts/massive-data/run_scaling.R"
test -s "$image"
mkdir -p "$parent" "$base/benchmark_logs"
root=$(mktemp -d "$parent/$(date -u +%Y%m%dT%H%M%SZ)_rep_XXXXXX")
rmdir "$root"
python3 "$suite/make_cases_representative.py" "$root" "$data_root"
touch "$root/preflight.required"
paths=()
for file in "${files[@]}"; do paths+=("$suite/$file"); done
while IFS= read -r -d '' path; do paths+=("$path"); done < <(
    find "$base/benchmark_scripts/massive-data/deep1b" \
        "$base/benchmark_scripts/massive-data/visualization" \
        -type f \( -name '*.R' -o -name '*.py' -o -name '*.sh' -o \
        -name '*.sbatch' -o -name '*.tsv' \) -print0 | sort -z
)
paths+=("$base/benchmark_scripts/massive-data/run_scaling.R")
sha256sum "$image" "${paths[@]}" > "$root/source.sha256"
sha256sum "${paths[@]}" > "$root/code.sha256"
printf 'stage\tjob_id\tcase_count\n' > "$root/jobs.tsv"
common=(--parsable --account="$account" --partition="$partition"
    --chdir="$base" --output="$base/benchmark_logs/feR_hnsw_%A_%a.out"
    --error="$base/benchmark_logs/feR_hnsw_%A_%a.err")
exported="ALL,HNSW_SUITE=$suite,HNSW_ROOT=$root,HNSW_IMAGE=$image"
exported+=",BIGANN_DATA_ROOT=$data_root"
preflight=$(sbatch "${common[@]}" --job-name=feR_hnsw_preflight
    --cpus-per-task=1 --mem=2G --time=00:20:00
    --export="$exported,HNSW_PHASE=preflight_5m" "$suite/worker.sbatch")
printf 'preflight\t%s\t1\n' "$preflight" >> "$root/jobs.tsv"
sweeps=()
for index in 0 1 2 3 4 5; do
    truth=$(sbatch "${common[@]}" --job-name=feR_hnsw_truth
        --dependency="afterok:$preflight" --array="$index"
        --cpus-per-task=8 --mem=24G --time=24:00:00
        --export="$exported,HNSW_PHASE=truth" "$suite/worker.sbatch")
    first=$((index * 5))
    last=$((first + 4))
    sweep=$(sbatch "${common[@]}" --job-name=feR_hnsw_sweep
        --dependency="afterok:$truth"
        --cpus-per-task=4 --mem=24G --time=2-00:00:00
        --export="$exported,HNSW_PHASE=sweep_bundle,HNSW_FIRST=$first,HNSW_LAST=$last" \
        "$suite/worker.sbatch")
    printf 'truth_%s\t%s\t1\n' "$index" "$truth" >> "$root/jobs.tsv"
    printf 'sweep_%s\t%s\t5\n' "$index" "$sweep" >> "$root/jobs.tsv"
    sweeps+=("$sweep")
done
dependency=$(IFS=:; echo "${sweeps[*]}")
audit=$(sbatch "${common[@]}" --job-name=feR_hnsw_audit
    --dependency="afterany:$dependency" --cpus-per-task=1
    --mem=4G --time=00:30:00
    --export="$exported,HNSW_PHASE=audit_representative"
    "$suite/worker.sbatch")
printf 'audit\t%s\t1\n' "$audit" >> "$root/jobs.tsv"
followup=$(sbatch "${common[@]}" --job-name=feR_hnsw_followup
    --dependency="afterany:$audit" --cpus-per-task=1
    --mem=2G --time=01:00:00
    --export="$exported,DEEP1B_BASE=$base" "$suite/followup.sbatch")
printf 'followup\t%s\t1\n' "$followup" >> "$root/jobs.tsv"
printf 'Campaign: %s\nAudit job: %s\nFollow-up: %s\n' \
    "$root" "$audit" "$followup"
