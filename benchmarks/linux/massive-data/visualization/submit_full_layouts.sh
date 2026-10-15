#!/usr/bin/env bash
# Submit read-only all-row render jobs for one fitted dataset size.
set -euo pipefail

[[ $# -eq 1 && "$1" =~ ^(1000000|5000000|10000000|100000000|1000000000)$ ]] || {
    echo "Usage: submit_full_layouts.sh 1000000|5000000|10000000|100000000|1000000000" >&2
    exit 2
}
rows=$1
base=${VIS_BASE:-/scratch/firenze/NN}
suite=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export VIS_SUITE=$suite
out=$base/fastEmbedR-results/massive-data/full_layouts/\
$(date -u +%Y%m%dT%H%M%SZ)_${rows}
mkdir -p "$out" "$base/benchmark_logs"
sha256sum "$base/singularity/fastembedr_cuda.sif" \
    "$suite/render_full_layouts.R" \
    "$suite/slurm_full_layouts.sh" > "$out/source.sha256"
job=$(sbatch --parsable --account="${VIS_ACCOUNT:-immunology}" \
    --partition="${VIS_PARTITION:-ada}" --chdir="$base" \
    --array=0-1%2 --output="$base/benchmark_logs/feR_fullplot_%A_%a.out" \
    --error="$base/benchmark_logs/feR_fullplot_%A_%a.err" \
    --export="ALL,VIS_BASE=$base,VIS_SUITE=$suite,VIS_OUT=$out,VIS_ROWS=$rows" \
    "$suite/slurm_full_layouts.sh")
printf 'Render job: %s\nOutput: %s\n' "$job" "$out"
