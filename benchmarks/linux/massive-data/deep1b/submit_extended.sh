#!/usr/bin/env bash
# Queue independent CPU and CUDA 100M-to-1B lanes after the 5M campaign.
set -euo pipefail

[[ $# -eq 1 ]] || {
    echo "Usage: submit_extended.sh FINISHED_AUTOMATIC_CAMPAIGN" >&2
    exit 2
}
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
previous=$(realpath "$1")
[[ "$(dirname "$previous")" == \
    "$base/fastEmbedR-results/massive-data/automatic" ]] || {
    echo "Expected a completed automatic 5M campaign." >&2
    exit 2
}
active=$(squeue -h -u "$USER" -o '%j')
if printf '%s\n' "$active" | grep -Eq '^feR_'; then
    echo "A fastEmbedR benchmark is already active." >&2
    exit 1
fi
parent=$base/fastEmbedR-results/massive-data/extended
mkdir -p "$parent" "$base/benchmark_logs"
root=$(mktemp -d "$parent/$(date -u +%Y%m%dT%H%M%SZ)_XXXXXX")
printf 'lane\tcontroller\tstate\n' > "$root/jobs.tsv"
printf 'previous=%s\n' "$previous" > "$root/launch.txt"
for lane in cpu cuda; do
    path=$root/$lane
    mkdir -p "$path"
    find "$suite" -type f \( -name '*.sh' -o -name '*.py' -o \
        -name '*.R' -o -name '*.tsv' -o -name '*.sbatch' \) \
        -print0 | sort -z | xargs -0 sha256sum > "$path/code.sha256"
    sha256sum "$base/benchmark_scripts/massive-data/run_scaling.R" \
        >> "$path/code.sha256"
    python3 "$suite/controller.py" init_extended "$path" \
        "$previous" "$lane" "$base"
done
for lane in cpu cuda; do
    path=$root/$lane
    job=$(sbatch --parsable \
        --account="${DEEP1B_CPU_ACCOUNT:-immunology}" \
        --partition="${DEEP1B_CPU_PARTITION:-ada}" --chdir="$base" \
        --job-name=feR_auto --cpus-per-task=1 --mem=2G \
        --time=00:20:00 \
        --output="$base/benchmark_logs/feR_auto_%j.out" \
        --error="$base/benchmark_logs/feR_auto_%j.err" \
        --export="ALL,DEEP1B_BASE=$base,DEEP1B_PIPELINE=$path,DEEP1B_STAGE=0" \
        "$suite/controller.sbatch")
    printf '%s\t%s\t%s\n' "$lane" "$job" "$path/state.json" \
        >> "$root/jobs.tsv"
done
echo "Extended campaign: $root"
cat "$root/jobs.tsv"
