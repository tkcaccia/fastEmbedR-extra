#!/usr/bin/env bash
# Start the entire queued CPU/GPU study after a finished HNSW refinement.
set -euo pipefail

[[ $# -eq 1 ]] || {
    echo "Usage: submit_automatic.sh REFINEMENT_CAMPAIGN" >&2
    exit 2
}
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
refinement=$(realpath "$1")
expected_parent=$base/fastEmbedR-results/massive-data/hnsw-autotune
[[ "$(dirname "$refinement")" == "$expected_parent" && \
    "$(basename "$refinement")" == *_refine5m_* ]] || {
    echo "Expected a refinement campaign under $base" >&2
    exit 2
}
repeats=${DEEP1B_TIMING_REPEATS:-3}
[[ "$repeats" =~ ^[1-9][0-9]*$ && "$repeats" -le 5 ]] || {
    echo "DEEP1B_TIMING_REPEATS must be 1 through 5." >&2
    exit 2
}
active=$(squeue -h -u "$USER" -o '%j')
if printf '%s\n' "$active" | grep -Eq '^feR_'; then
    echo "A fastEmbedR benchmark is already active." >&2
    exit 1
fi
test -s "$refinement/audit_refine.json"
mkdir -p "$base/fastEmbedR-results/massive-data/automatic" \
    "$base/benchmark_logs"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
root=$(mktemp -d \
    "$base/fastEmbedR-results/massive-data/automatic/${stamp}_XXXXXX")
find "$suite" "$base/benchmark_scripts/massive-data/hnsw-autotune" \
    -type f \( -name '*.sh' -o -name '*.py' -o -name '*.R' -o \
    -name '*.tsv' -o -name '*.sbatch' \) -print0 | sort -z | \
    xargs -0 sha256sum > "$root/code.sha256"
sha256sum "$base/benchmark_scripts/massive-data/run_scaling.R" \
    >> "$root/code.sha256"
python3 "$suite/controller.py" init "$root" "$refinement" \
    "$repeats" "$base"
job=$(sbatch --parsable \
    --account="${DEEP1B_CPU_ACCOUNT:-immunology}" \
    --partition="${DEEP1B_CPU_PARTITION:-ada}" --chdir="$base" \
    --job-name=feR_auto --cpus-per-task=1 --mem=2G \
    --time=00:20:00 \
    --output="$base/benchmark_logs/feR_auto_%j.out" \
    --error="$base/benchmark_logs/feR_auto_%j.err" \
    --export="ALL,DEEP1B_BASE=$base,DEEP1B_PIPELINE=$root,DEEP1B_STAGE=0" \
    "$suite/controller.sbatch")
echo "Automatic campaign: $root"
echo "First controller: $job"
echo "Stages: $(python3 -c \
    'import json,sys; print(len(json.load(open(sys.argv[1]))["plan"]))' \
    "$root/state.json")"
echo "Monitor: cat $root/state.json"
