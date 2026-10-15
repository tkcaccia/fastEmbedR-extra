#!/usr/bin/env bash
set -euo pipefail
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
rows=${DEEP1B_FULLGRAPH_ROWS:-5000000}
mode=${DEEP1B_FIT_MODE:-full}
default_rebuild=0
if [[ "$mode" == full && "$rows" -ge 100000000 ]]; then
    default_rebuild=1
fi
rebuild_knn=${DEEP1B_REBUILD_KNN_FOR_UMAP:-$default_rebuild}
backend_filter=${DEEP1B_BACKEND_FILTER:-all}
cpu_cores=${DEEP1B_CPU_CORES:-4}
job_memory=${DEEP1B_JOB_MEMORY:-64G}
gpu_devices=${DEEP1B_GPU_DEVICES:-}
dataset_filter=${1:-all}
after_job=${DEEP1B_AFTER_JOB:-}
dependency_type=${DEEP1B_DEPENDENCY_TYPE:-afterok}
[[ "$dependency_type" == afterok || \
   "$dependency_type" == afterany ]] || {
    echo "Invalid dependency type." >&2
    exit 2
}
if [[ -n "$after_job" &&
      ! "$after_job" =~ ^[0-9]+(:[0-9]+)*$ ]]; then
    echo "DEEP1B_AFTER_JOB must contain Slurm job IDs." >&2
    exit 2
fi
[[ "$dataset_filter" == all || "$dataset_filter" == deep || \
   "$dataset_filter" == turing ]] || {
    echo "Usage: submit_fullgraph5m.sh [deep|turing|all]" >&2
    exit 2
}
[[ "$mode" == full || "$mode" == full_tsne || \
   "$mode" == full_umap || "$mode" == pca || \
   "$mode" == classic ]] || {
    echo "Invalid DEEP1B_FIT_MODE." >&2
    exit 2
}
[[ "$rebuild_knn" == 0 || "$rebuild_knn" == 1 ]] || {
    echo "DEEP1B_REBUILD_KNN_FOR_UMAP must be 0 or 1." >&2
    exit 2
}
if [[ "$rebuild_knn" == 1 && "$mode" != full ]]; then
    echo "KNN rebuilding requires full mode." >&2
    exit 2
fi
[[ "$backend_filter" == all || "$backend_filter" == cpu || \
   "$backend_filter" == cuda ]] || exit 2
[[ "$cpu_cores" == 1 || "$cpu_cores" == 4 || \
   "$cpu_cores" == 8 || "$cpu_cores" == 16 ]] || {
    echo "DEEP1B_CPU_CORES must be 1, 4, 8, or 16." >&2
    exit 2
}
[[ "$job_memory" =~ ^[1-9][0-9]*G$ ]] || {
    echo "DEEP1B_JOB_MEMORY must be a positive number of GB." >&2
    exit 2
}
[[ -z "$gpu_devices" || "$gpu_devices" == 0 || \
   "$gpu_devices" == 0,1 || "$gpu_devices" == 0,1,2 || \
   "$gpu_devices" == 0,1,2,3 ]] || {
    echo "DEEP1B_GPU_DEVICES must be 0 through 0,1,2,3." >&2
    exit 2
}
if [[ -n "$gpu_devices" && "$backend_filter" != cuda ]]; then
    echo "GPU devices require the CUDA-only benchmark lane." >&2
    exit 2
fi
if [[ "$gpu_devices" == *,* && "$mode" == classic ]]; then
    echo "The classic route does not support multiple GPUs." >&2
    exit 2
fi
[[ "$rows" =~ ^[0-9]+$ && "$rows" -ge 1000 && \
   "$rows" -le 1000000000 ]] || {
    echo "Row count must be 1,000 to 1,000,000,000." >&2
    exit 2
}
if [[ "$mode" == classic && "$rows" != 1000000 ]]; then
    echo "Classic comparison is defined for 1 million rows." >&2
    exit 2
fi
first_row=${DEEP1B_FIRST_ROW:-1000001}
if [[ "$rows" == 1000000000 ]]; then first_row=1; fi
if ((first_row < 1 || first_row + rows - 1 > 1000000000)); then
    echo "Requested row window exceeds the source." >&2
    exit 2
fi
quota_free=${DEEP1B_QUOTA_FREE_BYTES:-}
quota_command=purequota
if ! command -v "$quota_command" >/dev/null; then
    quota_command=myquota
fi
if [[ -z "$quota_free" ]] && command -v "$quota_command" >/dev/null; then
    quota_free=$("$quota_command" | awk '$1 == "/scratch" {
        gsub(/GB/, "", $2); gsub(/GB/, "", $3)
        printf "%.0f", ($2 - $3) * 1000000000
    }')
fi
if [[ ! "$quota_free" =~ ^[0-9]+$ ]]; then
    echo "Set DEEP1B_QUOTA_FREE_BYTES or make purequota available." >&2
    exit 2
fi
test -s "$image"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
printf 'dataset\tbackend\tmode\trows\tjob\tcampaign\n'
for dataset in deep turing; do
    [[ "$dataset_filter" == all || \
       "$dataset_filter" == "$dataset" ]] || continue
    python3 "$suite/deep1b/validate_input.py" \
        "$base/Data/BigANN/$dataset/1000000000/base.1000000000.fbin" \
        --dataset "$dataset" >/dev/null
    label=$dataset
    if [[ "$dataset" == deep ]]; then label=deep1b; fi
    for backend in cpu cuda; do
        [[ "$backend_filter" == all || \
           "$backend_filter" == "$backend" ]] || continue
        parent=$base/fastEmbedR-results/massive-data/$label
        mkdir -p "$parent" "$base/benchmark_logs"
        root=$(mktemp -d \
            "$parent/${stamp}_${mode}${rows}_${backend}_XXXXXX")
        preflight_flags=()
        if [[ "$rebuild_knn" == 1 ]]; then
            preflight_flags+=(--rebuild-knn)
        fi
        if ! python3 "$suite/deep1b/preflight_fullgraph.py" \
            "$root" "$rows" "$mode" "${preflight_flags[@]}" \
            --quota-free-bytes "$quota_free" \
            > "$root/preflight.json"; then
            printf '%s\t%s\t%s\t%s\tBLOCKED\t%s\n' \
                "$dataset" "$backend" "$mode" "$rows" "$root"
            continue
        fi
        ln "$image" "$root/image.sif"
        if [[ -n "${DEEP1B_IMAGE_SHA256:-}" ]]; then
            printf '%s  %s\n' "$DEEP1B_IMAGE_SHA256" \
                "$root/image.sif" > "$root/image.sha256"
        else
            sha256sum "$root/image.sif" > "$root/image.sha256"
        fi
        sha256sum "$suite/deep1b/run_full_graph.R" \
            "$suite/deep1b/reclaim_fullgraph_storage.R" \
            "$suite/deep1b/run_classic_1m.R" \
            "$suite/deep1b/run_fullgraph_job.sh" \
            "$suite/deep1b/submit_fullgraph5m.sh" \
            "$suite/deep1b/submit_deep_rebuild.sh" \
            "$suite/deep1b/submit_20m.sh" \
            "$suite/deep1b/submit_storage_budgeted.py" \
            "$suite/deep1b/preflight_fullgraph.py" \
            "$suite/deep1b/gpu_memory.py" \
            "$suite/deep1b/disk_peak.py" \
            "$suite/deep1b/score.R" \
            "$suite/deep1b/score_fullgraph_leiden.R" \
            "$suite/visualization/render_full_layouts.R" \
            > "$root/source.sha256"
        export DEEP1B_FULLGRAPH_ROOT="$root" BIGANN_DATASET="$dataset"
        export DEEP1B_BACKEND="$backend" DEEP1B_FULLGRAPH_ROWS="$rows"
        export DEEP1B_FIT_MODE="$mode" DEEP1B_FIRST_ROW="$first_row"
        export DEEP1B_REBUILD_KNN_FOR_UMAP="$rebuild_knn"
        export DEEP1B_CPU_CORES="$cpu_cores"
        export DEEP1B_GPU_DEVICES="$gpu_devices"
        if ((rows >= 1000000000)); then
            export DEEP1B_MEMORY_LIMIT=64GB
        else
            export DEEP1B_MEMORY_LIMIT=8GB
        fi
        args=(--parsable --chdir="$base" --time=2-00:00:00 \
            --output="$base/benchmark_logs/feR_fg_%j.out" \
            --error="$base/benchmark_logs/feR_fg_%j.err" \
            --job-name="feR_fg_${dataset}_${backend}")
        if [[ -n "$after_job" ]]; then
            args+=(--dependency="$dependency_type:$after_job")
        fi
        if [[ "$backend" == cuda ]]; then
            gpu_count=1
            if [[ -n "$gpu_devices" ]]; then
                gpu_count=$((1 + ${#gpu_devices} / 2))
            fi
            args+=(--account="${DEEP1B_GPU_ACCOUNT:-l40sfree}" \
                --partition="${DEEP1B_GPU_PARTITION:-l40s}" \
                --gres="gpu:l40s:$gpu_count" \
                --cpus-per-task=4 --mem="$job_memory")
        else
            args+=(--account="${DEEP1B_CPU_ACCOUNT:-immunology}" \
                --partition="${DEEP1B_CPU_PARTITION:-ada}" \
                --cpus-per-task="$cpu_cores" --mem="$job_memory")
        fi
        job=$(sbatch "${args[@]}" --export=ALL \
            "$suite/deep1b/run_fullgraph_job.sh")
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$dataset" "$backend" "$mode" "$rows" "$job" "$root"
    done
done
