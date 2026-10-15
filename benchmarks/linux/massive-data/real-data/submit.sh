#!/usr/bin/env bash
# Independent preparation, CPU, one-GPU, and two-GPU lanes per dataset.
set -euo pipefail
base=${REAL_BASE:-/scratch/firenze/NN}
suite=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
image=$base/singularity/fastembedr_cuda.sif
common=$base/benchmark_scripts/fastembedr_jss_review_validation/common/common.R
runner=$base/benchmark_scripts/massive-data/run_scaling.R
monitor=$base/benchmark_scripts/massive-data/deep1b/gpu_memory.py
for path in "$image" "$common" "$runner" "$monitor" \
    "$suite/prepare.R" "$suite/run_classic.R" \
    "$suite/render_and_score.R" "$suite/plot_comparison.R" \
    "$suite/plan.py" \
    "$suite/case.sbatch" "$suite/prepare.sbatch" \
    "$suite/audit.py" "$suite/audit.sbatch" \
    "$suite/bundle.sbatch"; do
    test -s "$path" || { echo "Missing: $path" >&2; exit 1; }
done
root_parent=$base/fastEmbedR-results/massive-data/real-data
mkdir -p "$root_parent" "$base/benchmark_logs"
root=$(mktemp -d "$root_parent/$(date -u +%Y%m%dT%H%M%SZ)_XXXXXX")
python3 "$suite/plan.py" "$root"
sha256sum "$image" > "$root/image.sha256"
stat -Lc '%d:%i:%s:%Y:%Z' "$image" > "$root/image.stat"
sha256sum "$common" "$runner" "$monitor" \
    "$suite/prepare.R" "$suite/run_classic.R" \
    "$suite/render_and_score.R" "$suite/plot_comparison.R" \
    "$suite/plan.py" \
    "$suite/case.sbatch" "$suite/prepare.sbatch" \
    "$suite/audit.py" "$suite/audit.sbatch" \
    "$suite/bundle.sbatch" \
    > "$root/source.sha256"
printf 'dataset\tlane\tjob_id\tcases\n' > "$root/jobs.tsv"
for dataset in flow18 imagenet FlowRepository_FR-FCM-ZYRM_files; do
    prep_memory=16G
    classic_memory=32G
    if [[ "$dataset" == imagenet ]]; then
        prep_memory=48G
        classic_memory=64G
    elif [[ "$dataset" == flow18 ]]; then
        classic_memory=16G
    fi
    prep=$(sbatch --parsable --account="${REAL_CPU_ACCOUNT:-immunology}" \
        --partition="${REAL_CPU_PARTITION:-ada}" \
        --chdir="$base" --job-name="feR_real_prep" \
        --cpus-per-task=2 --mem="$prep_memory" --time=12:00:00 \
        --output="$base/benchmark_logs/feR_real_prep_%j.out" \
        --error="$base/benchmark_logs/feR_real_prep_%j.err" \
        --export="ALL,REAL_BASE=$base,REAL_ROOT=$root,REAL_SUITE=$suite,REAL_DATASET=$dataset" \
        "$suite/prepare.sbatch")
    printf '%s\tprep\t%s\t1\n' "$dataset" "$prep" \
        >> "$root/jobs.tsv"
    dependencies=()
    for lane in classic_cpu1 classic_cpu8 file_cpu1 file_cpu8 \
                classic_cuda1 file_cuda1 file_cuda2; do
        route=${lane%%_*}
        backend=${lane#*_}
        if [[ "$backend" == cpu8 ]]; then
            cores=8
        elif [[ "$backend" == cpu1 ]]; then
            cores=1
        else
            cores=4
        fi
        if [[ "$backend" == cpu* ]]; then
            selected=cpu
            account=${REAL_CPU_ACCOUNT:-immunology}
            partition=${REAL_CPU_PARTITION:-ada}
            memory=$classic_memory
            throttle=${REAL_CPU_THROTTLE:-8}
            gpu=()
            if [[ "$route" == file ]]; then memory=16G; fi
        else
            selected=cuda
            account=${REAL_GPU_ACCOUNT:-l40sfree}
            partition=${REAL_GPU_PARTITION:-l40s}
            memory=$classic_memory
            gpu=(--gres=gpu:l40s:1)
            if [[ "$route" == file ]]; then memory=16G; fi
            if [[ "$backend" == cuda2 ]]; then
                gpu=(--gres=gpu:l40s:2)
            fi
        fi
        case_file=$root/$dataset/cases_${lane}.tsv
        awk -F '\t' -v r="$route" -v b="$selected" \
            -v d="$backend" 'NR == 1 ||
            ($2 == r && $3 == b &&
             (($5 == "0,1") == (d == "cuda2")) &&
             (b == "cuda" || $4 == substr(d, 4)))' \
            "$root/$dataset/cases.tsv" > "$case_file"
        count=$(( $(wc -l < "$case_file") - 1 ))
        if ((count == 0)); then continue; fi
        common_args=(--parsable --account="$account" \
            --partition="$partition" --chdir="$base" \
            --job-name="feR_real_${lane}" --cpus-per-task="$cores" \
            --mem="$memory" \
            --dependency="afterany:$prep" \
            --export="ALL,REAL_BASE=$base,REAL_ROOT=$root,REAL_SUITE=$suite,REAL_DATASET=$dataset,REAL_CASE_FILE=$case_file")
        if [[ "$selected" == cuda ]]; then
            common_args+=("${gpu[@]}")
        fi
        if [[ "$selected" == cpu ]]; then
            job=$(sbatch "${common_args[@]}" --time=02:30:00 \
                --array="0-$((count - 1))%$throttle" \
                --output="$base/benchmark_logs/feR_real_%A_%a.out" \
                --error="$base/benchmark_logs/feR_real_%A_%a.err" \
                "$suite/case.sbatch")
        else
            hours=$((count * 2 + 1))
            job=$(sbatch "${common_args[@]}" \
                --time="$(printf '%02d:00:00' "$hours")" \
                --output="$base/benchmark_logs/feR_real_%j.out" \
                --error="$base/benchmark_logs/feR_real_%j.err" \
                "$suite/bundle.sbatch")
        fi
        printf '%s\t%s\t%s\t%s\n' "$dataset" "$lane" \
            "$job" "$count" >> "$root/jobs.tsv"
        dependencies+=("$job")
    done
    dependency=$(IFS=:; echo "${dependencies[*]}")
    audit=$(sbatch --parsable \
        --account="${REAL_CPU_ACCOUNT:-immunology}" \
        --partition="${REAL_CPU_PARTITION:-ada}" \
        --chdir="$base" --job-name="feR_real_audit" \
        --cpus-per-task=1 --mem=4G --time=00:30:00 \
        --dependency="afterany:$dependency" \
        --output="$base/benchmark_logs/feR_real_audit_%j.out" \
        --error="$base/benchmark_logs/feR_real_audit_%j.err" \
        --export="ALL,REAL_BASE=$base,REAL_ROOT=$root,REAL_SUITE=$suite,REAL_DATASET=$dataset" \
        "$suite/audit.sbatch")
    printf '%s\taudit\t%s\t1\n' "$dataset" "$audit" \
        >> "$root/jobs.tsv"
done
echo "Real-data campaign: $root"
cat "$root/jobs.tsv"
