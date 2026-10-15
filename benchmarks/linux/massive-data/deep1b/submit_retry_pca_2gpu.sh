#!/usr/bin/env bash
set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
expected=${DEEP1B_IMAGE_SHA256:-}
if [[ -z "$expected" ]]; then
    expected=0925105c3113c60225de70f948ad059dbcbd60ce3c4bccdd6286a366ab3131d8
fi
quota_free=${DEEP1B_QUOTA_FREE_BYTES:-}
[[ "$quota_free" =~ ^[0-9]+$ ]] || {
    echo 'Set DEEP1B_QUOTA_FREE_BYTES from myquota.' >&2
    exit 2
}
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -
input=$base/Data/BigANN/deep/1000000000/base.1000000000.fbin
python3 "$suite/deep1b/validate_input.py" "$input" \
    --dataset deep
parent=$base/fastEmbedR-results/massive-data/deep1b
mkdir -p "$parent" "$base/benchmark_logs"
root=$(mktemp -d \
    "$parent/$(date -u +%Y%m%dT%H%M%SZ)_pca20m_cuda2_retry_XXXXXX")
python3 "$suite/deep1b/preflight_fullgraph.py" \
    "$root" 20000000 pca --quota-free-bytes "$quota_free" \
    > "$root/preflight.json"
ln "$image" "$root/image.sif"
printf '%s  %s\n' "$expected" "$root/image.sif" \
    > "$root/image.sha256"
sha256sum \
    "$suite/deep1b/run_full_graph.R" \
    "$suite/deep1b/score.R" \
    "$suite/deep1b/verify_retry_pca_2gpu.R" \
    "$suite/deep1b/gpu_memory_allocated.py" \
    "$suite/deep1b/run_retry_pca_2gpu.sh" \
    "$suite/deep1b/submit_retry_pca_2gpu.sh" \
    "$suite/visualization/render_full_layouts.R" \
    > "$root/source.sha256"
export DEEP1B_BASE="$base" DEEP1B_RETRY_ROOT="$root"
job=$(sbatch --parsable --chdir="$base" \
    --account="${DEEP1B_GPU_ACCOUNT:-l40sfree}" \
    --partition="${DEEP1B_GPU_PARTITION:-l40s}" \
    --gres=gpu:l40s:2 --cpus-per-task=4 --mem=64G \
    --time=02:00:00 --job-name=feR_pca_2gpu_retry \
    --output="$base/benchmark_logs/feR_pca_2gpu_%j.out" \
    --error="$base/benchmark_logs/feR_pca_2gpu_%j.err" \
    --export=ALL "$suite/deep1b/run_retry_pca_2gpu.sh")
printf 'job=%s\ncampaign=%s\n' "$job" "$root"
