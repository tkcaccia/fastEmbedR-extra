#!/usr/bin/env bash

set -euo pipefail
phase=${1:-pilot}
dataset=${2:-deep}
[[ $# -le 2 ]] || {
    echo "Usage: submit.sh PHASE [deep|turing]" >&2
    exit 2
}
[[ "$phase" == pilot || "$phase" == scale || \
    "$phase" == scale10m || "$phase" == graph10m || \
    "$phase" == cluster_pilot || "$phase" == cluster_scale || \
    "$phase" == boundary || "$phase" == billion || \
    "$phase" == fresh5m || "$phase" == fresh5m_3d || \
    "$phase" == fresh5m_graph || \
    "$phase" == threads1m ]] || {
    echo "Unknown phase: $phase" >&2
    exit 2
}
[[ "$dataset" == deep || "$dataset" == turing ]] || {
    echo "Dataset must be deep or turing." >&2
    exit 2
}
lane=${DEEP1B_ONLY_BACKEND:-all}
[[ "$lane" == all || "$lane" == cpu || "$lane" == cuda ]] || {
    echo "DEEP1B_ONLY_BACKEND must be all, cpu, or cuda." >&2
    exit 2
}
serial=${DEEP1B_SERIALIZE:-0}
[[ "$serial" == 0 || "$serial" == 1 ]] || {
    echo "DEEP1B_SERIALIZE must be 0 or 1." >&2
    exit 2
}
case_filter=${DEEP1B_CASE_FILTER:-}
if [[ -n "$case_filter" && ! "$case_filter" =~ ^[a-z0-9_]+$ ]]; then
    echo "DEEP1B_CASE_FILTER must be one case name." >&2
    exit 2
fi
after_job=${DEEP1B_AFTER_JOB:-}
if [[ -n "$after_job" && ! "$after_job" =~ ^[0-9]+$ ]]; then
    echo "DEEP1B_AFTER_JOB must be one Slurm job ID." >&2
    exit 2
fi
if [[ "$phase" == threads1m && "$lane" == cuda ]]; then
    echo "threads1m is CPU-only." >&2
    exit 2
fi
if [[ "$phase" == billion && "${DEEP1B_ALLOW_BILLION:-0}" != 1 ]]; then
    echo "Set DEEP1B_ALLOW_BILLION=1 to submit billion-row cases." >&2
    exit 2
fi
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=${DEEP1B_SUITE:-$base/benchmark_scripts/massive-data/deep1b}
runner=${DEEP1B_RUNNER:-$base/benchmark_scripts/massive-data/run_scaling.R}
default_input=$base/Data/BigANN/$dataset/1000000000/base.1000000000.fbin
input=${DEEP1B_INPUT:-$default_input}
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
if [[ "$phase" == fresh5m_graph ]]; then
    truth_campaign=${DEEP1B_TRUTH_CAMPAIGN:?Set DEEP1B_TRUTH_CAMPAIGN}
    truth_file=$truth_campaign/truth/${dataset}_fresh5m.rds
    test -s "$truth_file" || {
        echo "Missing exact truth: $truth_file" >&2
        exit 1
    }
    read -r truth_image rest < "$truth_campaign/source.sha256"
    [[ "$truth_image" == "$(sha256sum "$image" | cut -d' ' -f1)" ]] || {
        echo "Graph and exact truth require the same image." >&2
        exit 1
    }
fi
awk -F '\t' 'NR > 1 && $3 == "cuda" && \
    ($4 == "umap" || $4 == "tsne") && $6 != 1 {
    print "CUDA projection must use one R core: " $1 > "/dev/stderr"
    invalid = 1
} END {exit invalid}' "$suite/cases.tsv"
validation=$(python3 "$suite/validate_input.py" "$input" \
    --dataset "$dataset")
echo "$validation"
test -s "$image"
test -s "$runner"
mkdir -p "$base/benchmark_logs"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
campaign_dataset=$dataset
if [[ "$dataset" == deep ]]; then
    campaign_dataset=deep1b
fi
parent=$base/fastEmbedR-results/massive-data/$campaign_dataset
mkdir -p "$parent"
root=$(mktemp -d "$parent/${stamp}_${phase}_${lane}_XXXXXX")
mkdir -p "$root/results"
ln "$image" "$root/image.sif" || {
    echo "Cannot pin the campaign image on the result filesystem." >&2
    exit 1
}
image=$root/image.sif
echo "Campaign: $root"
printf '%s\n' "$validation" > "$root/input.json"
cp "$suite/cases.tsv" "$root/registry.tsv"
if [[ "${FASTEMBEDR_IMAGE_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s  %s\n' "$FASTEMBEDR_IMAGE_SHA256" "$image" \
        > "$root/image.sha256"
else
    sha256sum "$image" > "$root/image.sha256"
fi
sha256sum "$suite/cases.tsv" \
    "$runner" \
    "$suite/run_case.sh" "$suite/score.R" \
    "$suite/score_cluster.R" \
    "$suite/score_knn_exact.R" "$suite/gpu_memory.py" \
    "$suite/prune_campaign.sh" \
    "$suite/validate_input.py" "$suite/preflight.R" \
    "$suite/audit_campaign.py" "$suite/slurm_preflight.sbatch" \
    "$suite/slurm_audit.sbatch" \
    "$suite/submit.sh" \
    "$suite/../visualization/render_full_layouts.R" \
    "$suite/slurm_case.sbatch" "$suite/slurm_bundle.sbatch" \
    > "$root/source.sha256"
first_row=1
if [[ "$phase" == fresh5m || "$phase" == fresh5m_3d || \
      "$phase" == fresh5m_graph ]]; then
    first_row=1000001
elif [[ "$phase" == scale10m ]]; then
    first_row=6000001
elif [[ "$phase" == graph10m ]]; then
    first_row=20000001
fi
printf 'dataset=%s\nphase=%s\nlane=%s\ninput=%s\nimage=%s\nfirst_row=%s\n' \
    "$dataset" "$phase" "$lane" "$input" "$image" "$first_row" \
    > "$root/launch.txt"
printf 'hnsw_m=%s\nhnsw_ef_construction=%s\nhnsw_ef_search=%s\n' \
    "${DEEP1B_HNSW_M:-auto}" "${DEEP1B_HNSW_EFC:-auto}" \
    "${DEEP1B_HNSW_EFS:-auto}" >> "$root/launch.txt"
printf 'cpu_node=%s\n' "${DEEP1B_CPU_NODE:-scheduler}" \
    >> "$root/launch.txt"
printf 'cpu_throttle=%s\n' "${DEEP1B_CPU_THROTTLE:-2}" \
    >> "$root/launch.txt"
printf 'case_filter=%s\nprune_billion=%s\n' \
    "$case_filter" "${DEEP1B_PRUNE_BILLION:-0}" \
    >> "$root/launch.txt"
if [[ "$phase" == fresh5m_graph ]]; then
    printf 'truth_campaign=%s\n' "$truth_campaign" >> "$root/launch.txt"
fi
printf 'kind\tjob_id\tcase_count\n' > "$root/jobs.tsv"
preflight_export="ALL,DEEP1B_BASE=$base,DEEP1B_IMAGE=$image"
preflight_export+=",DEEP1B_CAMPAIGN=$root,DEEP1B_PHASE=$phase"
preflight_dependency=()
if [[ -n "$after_job" ]]; then
    preflight_dependency=(--dependency="afterany:$after_job")
fi
preflight=$(sbatch --parsable --account="${DEEP1B_CPU_ACCOUNT:-immunology}" \
    --partition="${DEEP1B_CPU_PARTITION:-ada}" --chdir="$base" \
    --job-name="feR_${dataset}_pre" --cpus-per-task=1 --mem=2G \
    --time=00:20:00 "${preflight_dependency[@]}" \
    --output="$base/benchmark_logs/feR_${dataset}_pre_%j.out" \
    --error="$base/benchmark_logs/feR_${dataset}_pre_%j.err" \
    --export="$preflight_export" \
    "$suite/slurm_preflight.sbatch")
printf 'preflight\t%s\t1\n' "$preflight" >> "$root/jobs.tsv"

case "$phase" in
    pilot) limit=04:00:00 ;;
    scale) limit=16:00:00 ;;
    scale10m) limit=2-00:00:00 ;;
    graph10m) limit=2-00:00:00 ;;
    cluster_pilot) limit=04:00:00 ;;
    cluster_scale) limit=16:00:00 ;;
    boundary) limit=36:00:00 ;;
    billion) limit=48:00:00 ;;
    fresh5m) limit=16:00:00 ;;
    fresh5m_3d) limit=16:00:00 ;;
    fresh5m_graph) limit=48:00:00 ;;
    threads1m) limit=16:00:00 ;;
esac
workers=()
previous_cpu_job=
previous_job=
kinds=(cpu cuda cuda2)
if [[ "$phase" == threads1m ]]; then
    kinds=(cpu2 cpu4 cpu8 cpu12)
fi
for kind in "${kinds[@]}"; do
    if [[ "$kind" == cuda2 && \
          "${DEEP1B_SKIP_CUDA2:-0}" == 1 ]]; then
        continue
    fi
    if [[ "$lane" == cpu && "$kind" == cuda* ]] ||
        [[ "$lane" == cuda && "$kind" == cpu* ]]; then
        continue
    fi
    case_file=$root/cases_${kind}.tsv
    allocated_cores=4
    if [[ "$kind" == cpu* ]]; then
        if [[ "$kind" == cpu ]]; then
            awk -F '\t' -v p="$phase" 'NR == 1 ||
                ($2 == p && $3 == "cpu")' \
                "$suite/cases.tsv" > "$case_file"
        else
            allocated_cores=${kind#cpu}
            awk -F '\t' -v p="$phase" -v c="$allocated_cores" \
                'NR == 1 || ($2 == p && $3 == "cpu" && $6 == c)' \
                "$suite/cases.tsv" > "$case_file"
        fi
        account=${DEEP1B_CPU_ACCOUNT:-immunology}
        partition=${DEEP1B_CPU_PARTITION:-ada}
        throttle=${DEEP1B_CPU_THROTTLE:-2}
        if [[ "$phase" == threads1m ]]; then throttle=1; fi
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
    if [[ -n "$case_filter" ]]; then
        awk -F '\t' -v name="$case_filter" \
            'NR == 1 || $1 == name' "$case_file" \
            > "$case_file.filtered"
        mv "$case_file.filtered" "$case_file"
    fi
    count=$(($(wc -l < "$case_file") - 1))
    [[ "$count" -gt 0 ]] || continue
    if [[ "$serial" == 1 && \
          ( "$phase" == fresh5m || "$phase" == fresh5m_3d ) ]]; then
        limit=2-00:00:00
    fi
    if [[ "$phase" == billion ]]; then throttle=1; fi
    export DEEP1B_BASE="$base" DEEP1B_INPUT="$input"
    export DEEP1B_IMAGE="$image" DEEP1B_CAMPAIGN="$root"
    export DEEP1B_PHASE="$phase" DEEP1B_BACKEND="$backend"
    export DEEP1B_CASE_FILE="$case_file"
    export DEEP1B_FIRST_ROW="$first_row"
    export BIGANN_DATASET="$dataset"
    dependency="afterany:$preflight"
    if [[ "$serial" == 1 && -n "$previous_job" && \
          "$lane" != cuda ]]; then
        dependency="afterany:$previous_job"
    elif [[ "$phase" == threads1m && -n "$previous_cpu_job" ]]; then
        dependency="afterany:$previous_cpu_job"
    elif [[ "$serial" == 1 ]]; then
        dependency="afterany:$preflight"
    fi
    submit_args=(--parsable --account="$account" \
        --partition="$partition" --chdir="$base" \
        --job-name="feR_${dataset}" \
        --cpus-per-task="$allocated_cores" --mem=8G \
        --time="$limit" --dependency="$dependency")
    if [[ "$serial" == 1 ]]; then
        export DEEP1B_CASE_COUNT="$count"
        submit_args+=(--output="$base/benchmark_logs/feR_${dataset}_%j.out" \
            --error="$base/benchmark_logs/feR_${dataset}_%j.err")
        runner=$suite/slurm_bundle.sbatch
    else
        submit_args+=(--output="$base/benchmark_logs/feR_${dataset}_%A_%a.out" \
            --error="$base/benchmark_logs/feR_${dataset}_%A_%a.err")
        submit_args+=(--array="0-$((count - 1))%$throttle")
        runner=$suite/slurm_case.sbatch
    fi
    if [[ "$kind" == cuda* ]]; then
        submit_args+=("${gres[@]}")
    elif [[ -n "${DEEP1B_CPU_NODE:-}" ]]; then
        submit_args+=(--nodelist="$DEEP1B_CPU_NODE")
    fi
    job=$(sbatch "${submit_args[@]}" --export=ALL \
        "$runner")
    printf '%s\t%s\t%s\n' "$kind" "$job" "$count" \
        >> "$root/jobs.tsv"
    workers+=("$job")
    previous_job=$job
    if [[ "$phase" == threads1m ]]; then previous_cpu_job=$job; fi
done
if [[ "${#workers[@]}" -eq 0 ]]; then
    echo "No cases for $dataset/$phase/$lane" >&2
    exit 1
fi
dependency=$(IFS=:; echo "${workers[*]}")
audit=$(sbatch --parsable --account="${DEEP1B_CPU_ACCOUNT:-immunology}" \
    --partition="${DEEP1B_CPU_PARTITION:-ada}" --chdir="$base" \
    --job-name="feR_${dataset}_audit" --cpus-per-task=1 --mem=2G \
    --time=00:20:00 --dependency="afterany:$dependency" \
    --output="$base/benchmark_logs/feR_${dataset}_audit_%j.out" \
    --error="$base/benchmark_logs/feR_${dataset}_audit_%j.err" \
    --export="ALL,DEEP1B_BASE=$base,DEEP1B_CAMPAIGN=$root" \
    "$suite/slurm_audit.sbatch")
printf 'audit\t%s\t1\n' "$audit" >> "$root/jobs.tsv"
cat "$root/jobs.tsv"
