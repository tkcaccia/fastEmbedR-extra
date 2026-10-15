#!/usr/bin/env bash
# Submit exact truth, reused-index sweeps, and a final audit in one command.
set -euo pipefail

base=${HNSW_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/hnsw-autotune
image=${HNSW_IMAGE:-$base/singularity/fastembedr_cuda.sif}
data_root=${BIGANN_DATA_ROOT:-$base/Data/BigANN}
parent=$base/fastEmbedR-results/massive-data/hnsw-autotune
account=${HNSW_ACCOUNT:-immunology}
partition=${HNSW_PARTITION:-ada}
mkdir -p "$parent" "$base/benchmark_logs"
active=$(squeue -h -u "$USER" -o '%j')
if printf '%s\n' "$active" | grep -Eq '^feR_hnsw_'; then
    echo "An HNSW calibration campaign is already active." >&2
    exit 1
fi

files=()
for file in make_cases.py worker.R worker.sbatch audit.py \
    pilot_report.py submit.sh; do
    test -s "$suite/$file" || {
        echo "Missing suite file: $suite/$file" >&2
        exit 1
    }
    files+=("$suite/$file")
done
test -s "$image" || { echo "Missing image: $image" >&2; exit 1; }
root=$parent/$(date -u +%Y%m%dT%H%M%SZ)_$RANDOM
python3 "$suite/make_cases.py" "$root" "$data_root"
sha256sum "$image" "${files[@]}" > "$root/source.sha256"
sha256sum "${files[@]}" > "$root/code.sha256"
printf 'stage\tjob_id\tstate\n' > "$root/stages.tsv"
printf 'stage\tjob_id\tcase_count\n' > "$root/jobs.tsv"
common=(--parsable --account="$account" --partition="$partition"
    --chdir="$base" --output="$base/benchmark_logs/feR_hnsw_%A_%a.out"
    --error="$base/benchmark_logs/feR_hnsw_%A_%a.err")
export_vars="ALL,HNSW_SUITE=$suite,HNSW_ROOT=$root,HNSW_IMAGE=$image"
export_vars+=",BIGANN_DATA_ROOT=$data_root"
dependencies=()
for scope in pilot scale; do
    truth_indices=$(<"$root/${scope}_truth.indices")
    sweep_indices=$(<"$root/${scope}_sweep.indices")
    truth_count=$(awk -F, '{print NF}' <<< "$truth_indices")
    sweep_count=$(awk -F, '{print NF}' <<< "$sweep_indices")
    truth=$(sbatch "${common[@]}" --job-name=feR_hnsw_truth \
        --array="$truth_indices%2" --cpus-per-task=8 \
        --mem=12G --time=08:00:00 \
        --export="$export_vars,HNSW_PHASE=truth" "$suite/worker.sbatch")
    printf '%s_truth\t%s\tsubmitted\n' "$scope" "$truth" \
        >> "$root/stages.tsv"
    printf '%s_truth\t%s\t%s\n' "$scope" "$truth" "$truth_count" \
        >> "$root/jobs.tsv"
    sweep=$(sbatch "${common[@]}" --job-name=feR_hnsw_sweep \
        --dependency="afterany:$truth" \
        --array="$sweep_indices%8" --cpus-per-task=4 \
        --mem=12G --time=12:00:00 \
        --export="$export_vars,HNSW_PHASE=sweep" "$suite/worker.sbatch")
    printf '%s_sweep\t%s\tsubmitted\n' "$scope" "$sweep" \
        >> "$root/stages.tsv"
    printf '%s_sweep\t%s\t%s\n' "$scope" "$sweep" "$sweep_count" \
        >> "$root/jobs.tsv"
    dependencies+=("$sweep")
    if [[ "$scope" == pilot ]]; then
        early=$(sbatch "${common[@]}" \
            --job-name=feR_hnsw_pilot_report \
            --dependency="afterany:$sweep" --cpus-per-task=1 \
            --mem=2G --time=00:20:00 \
            --export="$export_vars,HNSW_PHASE=pilot_audit" \
            "$suite/worker.sbatch")
        printf 'pilot_audit\t%s\tsubmitted\n' "$early" \
            >> "$root/stages.tsv"
        printf 'pilot_audit\t%s\t1\n' "$early" \
            >> "$root/jobs.tsv"
    fi
done
joined=$(IFS=:; echo "${dependencies[*]}")
audit=$(sbatch "${common[@]}" --job-name=feR_hnsw_audit \
    --dependency="afterany:$joined" --cpus-per-task=1 \
    --mem=2G --time=00:20:00 \
    --export="$export_vars,HNSW_PHASE=audit" "$suite/worker.sbatch")
printf 'audit\t%s\tsubmitted\n' "$audit" >> "$root/stages.tsv"
printf 'audit\t%s\t1\n' "$audit" >> "$root/jobs.tsv"
printf 'Campaign: %s\nAudit: %s\n' "$root" "$audit"
cat "$root/jobs.tsv"
