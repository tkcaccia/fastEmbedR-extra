#!/usr/bin/env bash

set -euo pipefail
phase=${1:-pilot}
[[ "$phase" == pilot || "$phase" == scale || \
    "$phase" == boundary || "$phase" == billion ]] || {
    echo "Usage: submit.sh pilot|scale|boundary|billion" >&2
    exit 2
}
if [[ "$phase" == billion && "${DEEP1B_ALLOW_BILLION:-0}" != 1 ]]; then
    echo "Set DEEP1B_ALLOW_BILLION=1 to submit billion-row cases." >&2
    exit 2
fi
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
input=${DEEP1B_INPUT:-$base/Data/BigANN/deep/1000000000/base.1000000000.fbin}
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
python3 "$suite/validate_input.py" "$input"
test -s "$image"
test -s "$base/benchmark_scripts/massive-data/run_scaling.R"
mkdir -p "$base/benchmark_logs"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
root=$base/fastEmbedR-results/massive-data/deep1b/${stamp}_${phase}
mkdir -p "$root/results"
cp "$suite/cases.tsv" "$root/registry.tsv"
sha256sum "$image" "$suite/cases.tsv" \
    "$base/benchmark_scripts/massive-data/run_scaling.R" \
    "$suite/run_case.sh" "$suite/score.R" > "$root/source.sha256"
printf 'phase=%s\ninput=%s\nimage=%s\n' \
    "$phase" "$input" "$image" > "$root/launch.txt"
printf 'kind\tjob_id\tcase_count\n' > "$root/jobs.tsv"

case "$phase" in
    pilot) limit=04:00:00 ;;
    scale) limit=16:00:00 ;;
    boundary) limit=36:00:00 ;;
    billion) limit=48:00:00 ;;
esac
for kind in cpu cuda cuda2; do
    case_file=$root/cases_${kind}.tsv
    if [[ "$kind" == cpu ]]; then
        awk -F '\t' -v p="$phase" 'NR == 1 ||
            ($2 == p && $3 == "cpu")' "$suite/cases.tsv" > "$case_file"
        account=${DEEP1B_CPU_ACCOUNT:-immunology}
        partition=${DEEP1B_CPU_PARTITION:-ada}
        throttle=${DEEP1B_CPU_THROTTLE:-4}
        gres=()
        backend=cpu
    else
        if [[ "$kind" == cuda ]]; then
            awk -F '\t' -v p="$phase" 'NR == 1 ||
                ($2 == p && $3 == "cuda" && $10 == "-")' \
                "$suite/cases.tsv" > "$case_file"
            gres=(--gres=gpu:l40s:1)
        else
            awk -F '\t' -v p="$phase" 'NR == 1 ||
                ($2 == p && $3 == "cuda" && $10 != "-")' \
                "$suite/cases.tsv" > "$case_file"
            gres=(--gres=gpu:l40s:2)
        fi
        account=${DEEP1B_GPU_ACCOUNT:-l40sfree}
        partition=${DEEP1B_GPU_PARTITION:-l40s}
        throttle=${DEEP1B_GPU_THROTTLE:-2}
        if [[ "$kind" == cuda2 ]]; then
            throttle=${DEEP1B_GPU2_THROTTLE:-1}
        fi
        backend=cuda
    fi
    count=$(($(wc -l < "$case_file") - 1))
    [[ "$count" -gt 0 ]] || continue
    export DEEP1B_BASE="$base" DEEP1B_INPUT="$input"
    export DEEP1B_IMAGE="$image" DEEP1B_CAMPAIGN="$root"
    export DEEP1B_PHASE="$phase" DEEP1B_BACKEND="$backend"
    export DEEP1B_CASE_FILE="$case_file"
    job=$(sbatch --parsable --account="$account" \
        --partition="$partition" --chdir="$base" \
        --output="$base/benchmark_logs/feR_deep1b_%A_%a.out" \
        --error="$base/benchmark_logs/feR_deep1b_%A_%a.err" \
        --cpus-per-task=4 --mem=8G \
        --time="$limit" --array="0-$((count - 1))%$throttle" \
        "${gres[@]}" --export=ALL \
        "$suite/slurm_case.sbatch")
    printf '%s\t%s\t%s\n' "$kind" "$job" "$count" \
        >> "$root/jobs.tsv"
done
echo "Campaign: $root"
cat "$root/jobs.tsv"
