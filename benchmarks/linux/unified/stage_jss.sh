#!/usr/bin/env bash
# Submit shared preflights before the independent JSS campaign launchers.
set -euo pipefail

base=$(realpath "${FASTEMBEDR_BASE:-/scratch/firenze/NN}")
suite=$base/benchmark_scripts
root=$(realpath "${1:?Unified campaign root is required}")
[[ "$root" == "$base/fastEmbedR-results/unified/"* ]] || {
    echo 'JSS stage root is outside the unified result directory.' >&2
    exit 2
}
image=$base/singularity/fastembedr_cuda.sif
expected=${FASTEMBEDR_IMAGE_SHA256:?Image SHA-256 is required}
test -s "$image"
actual=$(sha256sum "$image" | awk '{print $1}')
[[ "$actual" == "$expected" ]] || {
    echo 'JSS preflight image changed after unified source lock.' >&2
    exit 3
}
test -s "$suite/jss-review-validation/slurm/run_preflight_cpu.sh"
mkdir -p "$root/jss_preflight" "$base/benchmark_logs"
ledger=$root/jss_stage_jobs.tsv
if [[ ! -f "$ledger" ]]; then
    printf 'role\tjob\n' > "$ledger"
    sha256sum "$suite/unified/stage_jss.sh" \
        "$suite/unified/launch_jss.sh" > "$root/jss_stage_source.sha256"
fi
recorded_job() {
    awk -F '\t' -v role="$1" '$1 == role {id = $2} END {print id}' \
        "$ledger"
}
submit_preflight() {
    local role=$1 script=$2 job
    job=$(recorded_job "$role")
    if [[ -z "$job" ]]; then
        job=$(sbatch --parsable --export="ALL,SUITE=$suite/jss-review-validation,BASE_DIR=$base,IMAGE=$image,OUTPUT_ROOT=$root/jss_preflight,FASTEMBEDR_IMAGE_SHA256=$expected" \
            "$suite/jss-review-validation/slurm/$script") || return 1
        printf '%s\t%s\n' "$role" "$job" >> "$ledger"
    fi
    printf '%s\n' "$job"
}
schedule_retry() {
    local -a gpu_jobs
    mapfile -t gpu_jobs < <(squeue -h -u "$USER" -p l40s \
        -o '%A' | sort -u)
    ((${#gpu_jobs[@]})) || {
        echo 'CUDA preflight blocked without a GPU job to wait for.' >&2
        exit 3
    }
    local joined command controller
    joined=$(IFS=:; echo "${gpu_jobs[*]}")
    printf -v command 'bash %q %q' "$suite/unified/stage_jss.sh" "$root"
    controller=$(sbatch --parsable --account=immunology --partition=ada \
        --cpus-per-task=1 --mem=2G --time=00:20:00 \
        --job-name=feR_JSS_stage_resume \
        --output="$base/benchmark_logs/feR_JSS_stage_%j.out" \
        --error="$base/benchmark_logs/feR_JSS_stage_%j.err" \
        --dependency="afterany:$joined" --export=ALL \
        --wrap="$command")
    printf 'resume\t%s\n' "$controller" >> "$ledger"
    printf 'JSS GPU preflight deferred to controller %s.\n' "$controller"
}
cpu=$(submit_preflight cpu run_preflight_cpu.sh)
gpu=$(recorded_job cuda)
if [[ -z "$gpu" ]]; then
    if ! gpu=$(submit_preflight cuda run_preflight_cuda.sh 2>&1); then
        if grep -q 'QOSMaxGRESPerUser' <<< "$gpu"; then
            schedule_retry
            exit 0
        fi
        echo "$gpu" >&2
        exit 3
    fi
fi
for role in paired extended; do
    [[ -z "$(recorded_job "$role")" ]] || continue
    job=$(sbatch --parsable --account=immunology --partition=ada \
        --cpus-per-task=1 --mem=8G --time=02:00:00 \
        --job-name="feR_JSS_${role}_launch" \
        --output="$root/jss_${role}_controller_%j.out" \
        --error="$root/jss_${role}_controller_%j.err" \
        --dependency="afterok:$cpu:$gpu" --export=ALL \
        "$suite/unified/launch_jss.sh" "$root" "$role")
    printf '%s\t%s\n' "$role" "$job" >> "$ledger"
done
printf 'JSS preflight and launch jobs: %s\n' "$ledger"
