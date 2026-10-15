#!/usr/bin/env bash
# Submit four source-locked dataset/backend lanes.
set -euo pipefail

[[ $# -le 2 ]] || {
    echo "Usage: submit_comprehensive.sh [TIMING_REPEATS]" \
        "[cpu|cuda|all]" >&2
    exit 2
}
repeats=${1:-3}
selected_lane=${2:-all}
[[ "$repeats" =~ ^[1-9][0-9]*$ ]] || {
    echo "TIMING_REPEATS must be a positive integer." >&2
    exit 2
}
[[ "$selected_lane" == all || "$selected_lane" == cpu || \
    "$selected_lane" == cuda ]] || {
    echo "Backend must be cpu, cuda, or all." >&2
    exit 2
}
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export DEEP1B_SUITE=$suite
export VIS_SUITE=$suite/visualization
export DEEP1B_RUNNER=$suite/run_scaling.R
export DEEP1B_CPU_THROTTLE=${DEEP1B_CPU_THROTTLE:-4}
image=$base/singularity/fastembedr_cuda.sif
test -s "$VIS_SUITE/render_full_layouts.R"
test -s "$VIS_SUITE/test_render_full_layouts.R"
test -s "$DEEP1B_RUNNER"
test -s "$image"
python3 "$suite/validate_input.py" \
    "$base/Data/BigANN/deep/1000000000/base.1000000000.fbin" \
    --dataset deep
python3 "$suite/validate_input.py" \
    "$base/Data/BigANN/turing/1000000000/base.1000000000.fbin" \
    --dataset turing

parent=$base/fastEmbedR-results/massive-data/comprehensive
mkdir -p "$parent" "$base/benchmark_logs"
root=$(mktemp -d "$parent/$(date -u +%Y%m%dT%H%M%SZ)_XXXXXX")
ln "$image" "$root/image.sif" || {
    echo "Cannot pin the campaign image on the result filesystem." >&2
    exit 1
}
export DEEP1B_IMAGE=$root/image.sif
export FASTEMBEDR_IMAGE_SHA256
FASTEMBEDR_IMAGE_SHA256=$(sha256sum "$DEEP1B_IMAGE" | cut -d' ' -f1)
printf 'lane\tdataset\tcontroller\tstate\n' > "$root/jobs.tsv"
printf '%s  %s\n' "$FASTEMBEDR_IMAGE_SHA256" "$DEEP1B_IMAGE" \
    > "$root/image.sha256"
lanes=(cpu cuda)
if [[ "$selected_lane" != all ]]; then
    lanes=("$selected_lane")
fi
for lane in "${lanes[@]}"; do
    for dataset in deep turing; do
        path=$root/$lane/$dataset
        mkdir -p "$path"
        find "$suite" -type f \( -name '*.sh' -o -name '*.py' -o \
            -name '*.R' -o -name '*.tsv' -o -name '*.sbatch' \) \
            -print0 | sort -z | xargs -0 sha256sum \
            > "$path/code.sha256"
        python3 "$suite/controller.py" init_comprehensive "$path" \
            "$lane" "$repeats" "$base" "$dataset"
        controller_export="ALL,DEEP1B_BASE=$base,DEEP1B_PIPELINE=$path"
        controller_export+=",DEEP1B_STAGE=0"
        job=$(sbatch --parsable \
            --account="${DEEP1B_CPU_ACCOUNT:-immunology}" \
            --partition="${DEEP1B_CPU_PARTITION:-ada}" \
            --chdir="$base" --job-name="feR_${lane}_${dataset}_ctl" \
            --cpus-per-task=1 --mem=2G --time=00:20:00 \
            --output="$base/benchmark_logs/feR_${lane}_ctl_%j.out" \
            --error="$base/benchmark_logs/feR_${lane}_ctl_%j.err" \
            --export="$controller_export" \
            "$suite/controller.sbatch")
        printf '%s\t%s\t%s\t%s\n' "$lane" "$dataset" \
            "$job" "$path/state.json" >> "$root/jobs.tsv"
    done
done
echo "Comprehensive campaign: $root"
cat "$root/jobs.tsv"
