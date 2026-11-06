#!/usr/bin/env bash
# One submission for independent Deep1B CPU and GPU full-row lanes.
set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
scheduler=$(realpath "${BASH_SOURCE[0]}")
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
rows_list=(1000000 10000000)
lane_group=${DEEP1B_LANE_GROUP:-all}
bundle_short=${DEEP1B_BUNDLE_SHORT_CUDA:-0}
[[ "$bundle_short" == 0 || "$bundle_short" == 1 ]] || {
    echo 'DEEP1B_BUNDLE_SHORT_CUDA must be 0 or 1.' >&2
    exit 2
}
case "$lane_group" in
    all) lanes=(cpu16 cpu8 cpu4 cuda1 cuda2) ;;
    cpu) lanes=(cpu16 cpu8 cpu4) ;;
    cuda) lanes=(cuda1 cuda2) ;;
    *) echo 'DEEP1B_LANE_GROUP must be all, cpu, or cuda.' >&2
       exit 2 ;;
esac

case_details() {
    local lane=$1
    backend=cpu cores=4 devices=
    case "$lane" in
        cpu4) cores=4 ;;
        cpu8) cores=8 ;;
        cpu16) cores=16 ;;
        cuda1) backend=cuda cores=1 devices=0 ;;
        cuda2) backend=cuda cores=1 devices=0,1 ;;
        *) echo "Unknown lane: $lane" >&2; exit 2 ;;
    esac
}

case_memory() {
    echo 64G
}

case_time() {
    if [[ "$3" == cpu* ]]; then
        echo 3-00:00:00
    elif [[ "$2" == 10000000 && "$3" == cuda* ]]; then
        echo 08:00:00
    elif [[ "$2" == 1000000 && "$3" == cuda* ]]; then
        if [[ "$bundle_short" == 1 && "$3" == cuda1 ]]; then
            echo 02:00:00
        else
            echo 04:00:00
        fi
    else
        echo 2-00:00:00
    fi
}

print_plan() {
    printf 'mode\trows\tlane\tbackend\tcores\tdevices\t'
    printf 'job_memory\tjob_time\tdepends_on\tallocation\n'
    if [[ "$lane_group" == cpu || "$lane_group" == all ]]; then
        printf 'classic\t1000000\tcpu4\tcpu\t4\t-\t64G\t'
        printf '%s\t-\tseparate\n' \
            "$(case_time classic 1000000 cpu4)"
    fi
    if [[ "$lane_group" != cpu ]]; then
        local allocation=separate
        [[ "$bundle_short" == 0 ]] || allocation=short_cuda1
        printf 'classic\t1000000\tcuda1\tcuda\t1\t0\t64G\t%s\t-\t%s\n' \
            "$(case_time classic 1000000 cuda1)" "$allocation"
    fi
    local lane rows depends memory
    for lane in "${lanes[@]}"; do
        case_details "$lane"
        for rows in "${rows_list[@]}"; do
            depends=-
            memory=$(case_memory full "$rows" "$lane")
            allocation=separate
            if [[ "$bundle_short" == 1 && "$lane" == cuda1 &&
                  "$rows" == 1000000 ]]; then
                allocation=short_cuda1
            fi
            printf 'full\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$rows" "$lane" "$backend" "$cores" \
                "${devices:--}" "$memory" \
                "$(case_time full "$rows" "$lane")" \
                "$depends" "$allocation"
        done
    done
}

if [[ "${1:-}" == --plan ]]; then
    [[ $# == 1 ]] || exit 2
    print_plan
    exit 0
fi
if [[ "$lane_group" != cpu &&
      "${FASTEMBEDR_HPC_GPU_PAUSED:-1}" != 0 ]]; then
    echo 'UCT GPU submissions remain paused; use the CPU lane only.' >&2
    exit 2
fi
resume_ledger=
if [[ "${1:-}" == --resume && $# == 2 ]]; then
    resume_ledger=$2
elif [[ $# != 0 ]]; then
    echo 'Usage: submit_matrix.sh [--plan|--resume JOBS.tsv]' >&2
    exit 2
fi
[[ -s "$image" && -s "$suite/submit_fullgraph5m.sh" ]] || {
    echo 'Image or Deep1B suite is missing.' >&2
    exit 2
}
case "$lane_group" in
    cpu) active_pattern='^feR_fg_deep_cpu$' ;;
    cuda) active_pattern='^feR_fg_deep_cuda$' ;;
    all) active_pattern='^feR_fg_deep_(cpu|cuda)$' ;;
esac
if [[ -z "$resume_ledger" ]] &&
   squeue -h -u "$USER" -o '%j' | \
       grep -E "$active_pattern" >/dev/null; then
    echo "An earlier $lane_group full-graph job is still active." >&2
    exit 2
fi
quota_free=${DEEP1B_QUOTA_FREE_BYTES:-}
if [[ -n "$resume_ledger" ]]; then quota_free=; fi
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
[[ "$quota_free" =~ ^[0-9]+$ ]] || {
    echo 'Set DEEP1B_QUOTA_FREE_BYTES from purequota.' >&2
    exit 2
}
physical_free=$(df -B1 --output=avail "$base" | tail -n 1)
available=$((quota_free < physical_free ? quota_free : physical_free))
read -r reserved required < <(python3 - "$suite" \
    "$lane_group" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1])))
from preflight_fullgraph import storage_plan

large = storage_plan(10_000_000, "full", 10**15)[
    "worst_case_bytes"]
group = sys.argv[2]
if group == "cpu":
    peak = 3 * large
elif group == "cuda":
    peak = 2 * large
else:
    peak = 5 * large
peak += 20_000_000_000
peak += 3 * 30_000_000_000  # Graph and clustering reserve.
peak += 100_000_000_000  # Other scratch activity reserve.
print(peak, (peak * 20 + 16) // 17)
PY
)
if [[ -z "$resume_ledger" ]] && ((available < required)); then
    printf 'Need %s free bytes for independent lanes; have %s.\n' \
        "$required" "$available" >&2
    exit 3
fi
digest=$(sha256sum "$image" | awk '{print $1}')
if [[ -n "${DEEP1B_IMAGE_SHA256:-}" &&
      "$DEEP1B_IMAGE_SHA256" != "$digest" ]]; then
    echo 'Configured image SHA-256 does not match the image.' >&2
    exit 3
fi
python3 "$suite/validate_input.py" \
    "$base/Data/BigANN/deep/1000000000/base.1000000000.fbin" \
    --dataset deep >/dev/null
export DEEP1B_BASE="$base" DEEP1B_IMAGE="$image"
export DEEP1B_IMAGE_SHA256="$digest"
export DEEP1B_QUOTA_FREE_BYTES="$quota_free"
export DEEP1B_FIRST_ROW=1000001 DEEP1B_SMOKE=0
export DEEP1B_DEPENDENCY_TYPE=afterok
if [[ -n "$resume_ledger" ]]; then
    ledger=$(dirname "$(realpath "$resume_ledger")")
    matrix_root=$(realpath \
        "$base/fastEmbedR-results/massive-data/deep1b_matrix")
    [[ "$ledger" == "$matrix_root/"* ]] || {
        echo 'Resume ledger is outside the Deep1B matrix root.' >&2
        exit 2
    }
    expected=$(sed -n 's/^image_sha256=//p' "$ledger/identity.txt")
    [[ "$expected" == "$digest" ]] || {
        echo 'Resume image differs from the source-locked matrix.' >&2
        exit 3
    }
    expected_group=$(sed -n 's/^lane_group=//p' "$ledger/identity.txt")
    [[ "$expected_group" == "$lane_group" ]] || {
        echo 'Resume lane group differs from the original matrix.' >&2
        exit 3
    }
    expected_bundle=$(sed -n 's/^bundle_short_cuda=//p' \
        "$ledger/identity.txt")
    [[ "$expected_bundle" == "$bundle_short" ]] || {
        echo 'Resume bundle policy differs from the original matrix.' >&2
        exit 3
    }
    awk -v scheduler="$scheduler" \
        '$2 != scheduler' "$ledger/source.sha256" | \
        sha256sum -c - >/dev/null || {
        echo 'Deep1B runner changed after matrix submission.' >&2
        exit 3
    }
    sha256sum "$scheduler" \
        >> "$ledger/resume_source.sha256"
else
    ledger=$base/fastEmbedR-results/massive-data/deep1b_matrix/
    ledger+=$(date -u +%Y%m%dT%H%M%SZ)
    mkdir -p "$ledger"
    print_plan > "$ledger/plan.tsv"
    printf 'image_sha256=%s\nlane_group=%s\n' \
        "$digest" "$lane_group" \
        > "$ledger/identity.txt"
    printf 'bundle_short_cuda=%s\nreserved_peak_bytes=%s\n' \
        "$bundle_short" "$reserved" \
        >> "$ledger/identity.txt"
    sha256sum "$scheduler" \
        "$suite/submit_fullgraph5m.sh" \
        "$suite/submit_short_cuda_bundle.sh" \
        "$suite/run_short_cuda_bundle.sh" \
        "$suite/run_fullgraph_job.sh" \
        "$suite/audit_output.R" \
        "$suite/run_full_graph.R" > "$ledger/source.sha256"
    printf 'mode\trows\tlane\tjob\tcampaign\tjob_memory\tdependency\n' \
        > "$ledger/jobs.tsv"
fi

printf 'Matrix ledger: %s\n' "$ledger/jobs.tsv"
declare -A submitted
if [[ -n "$resume_ledger" ]]; then
    while IFS=$'\t' read -r mode rows lane job campaign memory dependency; do
        [[ "$job" =~ ^[0-9]+$ ]] || continue
        submitted["${mode}_${lane}_${rows}"]=$job
    done < "$ledger/jobs.tsv"
fi
submit_case() {
    local mode=$1 rows=$2 lane=$3 dependency=$4
    [[ -z "${submitted["${mode}_${lane}_${rows}"]:-}" ]] || return 0
    case_details "$lane"
    local output record job campaign memory time_limit
    memory=$(case_memory "$mode" "$rows" "$lane")
    time_limit=$(case_time "$mode" "$rows" "$lane")
    if ! output=$(DEEP1B_FIT_MODE="$mode" \
        DEEP1B_FULLGRAPH_ROWS="$rows" \
        DEEP1B_BACKEND_FILTER="$backend" \
        DEEP1B_CPU_CORES="$cores" \
        DEEP1B_GPU_DEVICES="$devices" \
        DEEP1B_JOB_MEMORY="$memory" \
        DEEP1B_JOB_TIME="$time_limit" \
        DEEP1B_AFTER_JOB="$dependency" \
        bash "$suite/submit_fullgraph5m.sh" deep 2>&1); then
        echo "$output" >&2
        exit 3
    fi
    record=$(printf '%s\n' "$output" | awk -F '\t' \
        -v route="$backend" '$1 == "deep" && $2 == route')
    [[ -n "$record" ]] || { echo "$output" >&2; exit 1; }
    job=$(printf '%s\n' "$record" | cut -f 5)
    campaign=$(printf '%s\n' "$record" | cut -f 6)
    [[ "$job" =~ ^[0-9]+$ ]] || {
        echo "Submission blocked: $mode $rows $lane" >&2
        exit 3
    }
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$mode" "$rows" "$lane" "$job" "$campaign" \
        "$memory" "${dependency:--}" >> "$ledger/jobs.tsv"
    submitted["${mode}_${lane}_${rows}"]=$job
}
submit_short_bundle() {
    [[ -z "${submitted[classic_cuda1_1000000]:-}" &&
       -z "${submitted[full_cuda1_1000000]:-}" ]] || {
        [[ -n "${submitted[classic_cuda1_1000000]:-}" &&
           -n "${submitted[full_cuda1_1000000]:-}" ]] && return 0
        echo 'Incomplete short CUDA bundle ledger; repair before resume.' >&2
        exit 3
    }
    local output classic_record full_record job classic_root full_root
    if ! output=$(bash "$suite/submit_short_cuda_bundle.sh" deep 2>&1); then
        echo "$output" >&2
        exit 3
    fi
    classic_record=$(awk -F '\t' '$1 == "deep" && $2 == "cuda" &&
        $3 == "classic" {print}' <<< "$output")
    full_record=$(awk -F '\t' '$1 == "deep" && $2 == "cuda" &&
        $3 == "full" {print}' <<< "$output")
    [[ -n "$classic_record" && -n "$full_record" ]] || {
        echo "Short CUDA bundle returned incomplete case records." >&2
        exit 3
    }
    job=$(cut -f 5 <<< "$classic_record")
    [[ "$job" =~ ^[0-9]+$ &&
       "$(cut -f 5 <<< "$full_record")" == "$job" ]] || {
        echo 'Short CUDA cases did not share one Slurm job.' >&2
        exit 3
    }
    classic_root=$(cut -f 6 <<< "$classic_record")
    full_root=$(cut -f 6 <<< "$full_record")
    {
        printf 'classic\t1000000\tcuda1\t%s\t%s\t64G\t-\n' \
            "$job" "$classic_root"
        printf 'full\t1000000\tcuda1\t%s\t%s\t64G\t-\n' \
            "$job" "$full_root"
    } >> "$ledger/jobs.tsv"
    submitted[classic_cuda1_1000000]=$job
    submitted[full_cuda1_1000000]=$job
}

if [[ "$lane_group" == cpu || "$lane_group" == all ]]; then
    submit_case classic 1000000 cpu4 ''
fi
if [[ "$lane_group" != cpu ]]; then
    if [[ "$bundle_short" == 1 ]]; then
        submit_short_bundle
    else
        submit_case classic 1000000 cuda1 ''
    fi
fi
for lane in "${lanes[@]}"; do
    for rows in "${rows_list[@]}"; do
        if [[ "$bundle_short" == 1 && "$lane" == cuda1 &&
              "$rows" == 1000000 ]]; then
            continue
        fi
        submit_case full "$rows" "$lane" ''
    done
done
printf 'Submitted Deep1B matrix: %s\n' "$ledger/jobs.tsv"
