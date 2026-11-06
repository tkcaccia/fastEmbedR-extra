#!/usr/bin/env bash
# Submit shared preflights before the independent JSS campaign launchers.
set -euo pipefail
echo "policy_rejected: archived unified HPC campaign includes file-backed work." >&2
exit 78

[[ "${FASTEMBEDR_HPC_GPU_PAUSED:-1}" == 0 ]] || {
    echo 'UCT GPU submissions remain paused, including JSS controllers.' >&2
    exit 2
}

[[ "${FASTEMBEDR_HPC_GPU_PAUSED:-1}" == 0 ]] || {
    echo 'UCT GPU submissions remain paused, including JSS controllers.' >&2
    exit 2
}

base=$(realpath "${FASTEMBEDR_BASE:-/scratch/firenze/NN}")
suite=$(realpath "${FASTEMBEDR_SUITE_ROOT:-$base/benchmark_scripts}")
root=$(realpath "${1:?Unified campaign root is required}")
[[ "$root" == "$base/fastEmbedR-results/unified/"* ]] || {
    echo 'JSS stage root is outside the unified result directory.' >&2
    exit 2
}
image=${FASTEMBEDR_IMAGE:-$base/singularity/fastembedr_cuda.sif}
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
else
    sha256sum -c "$root/jss_stage_source.sha256" >/dev/null || {
        echo 'JSS stage source changed after submission.' >&2
        exit 3
    }
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
prior_cpu=$(recorded_job cpu)
prior_gpu=$(recorded_job cuda)
cpu=$(submit_preflight cpu run_preflight_cpu.sh)
gpu=$(recorded_job cuda)
if [[ -z "$gpu" ]]; then
    if ! gpu=$(submit_preflight cuda run_preflight_cuda.sh 2>&1); then
        echo "$gpu" >&2
        exit 3
    fi
fi
dependency_ids=()
for role in cpu cuda; do
    job=$(recorded_job "$role")
    prior=$prior_cpu
    [[ "$role" != cuda ]] || prior=$prior_gpu
    record=$(sacct -X -n -P -j "$job" -o JobID,State,ExitCode \
        2>/dev/null || true)
    state=$(awk -F '|' -v id="$job" '$1 == id {
        print $2 "|" $3; exit
    }' <<< "$record")
    if [[ "$state" == 'COMPLETED|0:0' ]]; then
        identity=$root/jss_preflight/identity/$role/identity.csv
        python3 - "$identity" "$expected" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="") as stream:
    row = next(csv.DictReader(stream))
if row["image_sha256"] != sys.argv[2] or \
        row["package_version"] != "0.1":
    raise SystemExit("Completed preflight has a different image or version")
PY
    elif [[ "$state" =~ ^(PENDING|RUNNING|CONFIGURING|COMPLETING)\| ]] ||
         [[ -z "$state" && -z "$prior" ]]; then
        dependency_ids+=("$job")
    else
        echo "$role preflight $job is not verifiably active: $state" >&2
        exit 3
    fi
done
dependency=''
if ((${#dependency_ids[@]})); then
    dependency="afterok:$(IFS=:; echo "${dependency_ids[*]}")"
else
    BASE_DIR="$base" IMAGE="$image" \
      OUTPUT_ROOT="$root/jss_preflight" \
      bash "$suite/jss-review-validation/verify_preflight.sh" >/dev/null
fi
roles=${JSS_ROLES:-"paired extended"}
for role in $roles; do
    case "$role" in
        paired|extended) ;;
        *) echo "Unknown JSS role: $role" >&2; exit 2 ;;
    esac
    [[ -z "$(recorded_job "$role")" ]] || continue
    command=(sbatch --parsable --account=immunology --partition=ada \
        --cpus-per-task=1 --mem=8G --time=02:00:00 \
        --job-name="feR_JSS_${role}_launch" \
        --output="$root/jss_${role}_controller_%j.out" \
        --error="$root/jss_${role}_controller_%j.err" \
        --export=ALL)
    [[ -z "$dependency" ]] || command+=(--dependency="$dependency")
    job=$("${command[@]}" "$suite/unified/launch_jss.sh" \
        "$root" "$role")
    printf '%s\t%s\n' "$role" "$job" >> "$ledger"
done
printf 'JSS preflight and launch jobs: %s\n' "$ledger"
