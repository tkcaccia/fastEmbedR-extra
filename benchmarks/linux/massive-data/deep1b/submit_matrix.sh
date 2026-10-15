#!/usr/bin/env bash
# One submission for independent Deep1B CPU and GPU full-row lanes.
set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
rows_list=(1000000 10000000 50000000 100000000)
lanes=(cpu4 cpu8 cpu16 cuda1 cuda2 cuda4)

case_details() {
    local lane=$1
    backend=cpu cores=4 devices=
    case "$lane" in
        cpu4) cores=4 ;;
        cpu8) cores=8 ;;
        cpu16) cores=16 ;;
        cuda1) backend=cuda cores=1 devices=0 ;;
        cuda2) backend=cuda cores=1 devices=0,1 ;;
        cuda4) backend=cuda cores=1 devices=0,1,2,3 ;;
        *) echo "Unknown lane: $lane" >&2; exit 2 ;;
    esac
}

print_plan() {
    printf 'mode\trows\tlane\tbackend\tcores\tdevices\tdepends_on\n'
    printf 'classic\t1000000\tcpu4\tcpu\t4\t-\t-\n'
    printf 'classic\t1000000\tcuda1\tcuda\t1\t0\t-\n'
    local lane rows prior depends
    for lane in "${lanes[@]}"; do
        case_details "$lane"
        prior=-
        for rows in "${rows_list[@]}"; do
            depends=-
            if ((rows >= 50000000)); then depends=$prior; fi
            if [[ "$lane" == cpu16 && "$rows" == 100000000 ]]; then
                depends+=,cpu4_100000000
            fi
            if [[ "$lane" == cuda4 && "$rows" == 100000000 ]]; then
                depends+=,cuda2_100000000
            fi
            printf 'full\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$rows" "$lane" "$backend" "$cores" \
                "${devices:--}" "$depends"
            prior="${lane}_${rows}"
        done
    done
}

if [[ "${1:-}" == --plan ]]; then
    [[ $# == 1 ]] || exit 2
    print_plan
    exit 0
fi
[[ $# == 0 ]] || { echo 'Usage: submit_matrix.sh [--plan]' >&2; exit 2; }
[[ -s "$image" && -s "$suite/submit_fullgraph5m.sh" ]] || {
    echo 'Image or Deep1B suite is missing.' >&2
    exit 2
}
if squeue -h -u "$USER" -o '%j' | grep '^feR_fg_' >/dev/null; then
    echo 'An earlier full-graph job is still active.' >&2
    exit 2
fi
quota_free=${DEEP1B_QUOTA_FREE_BYTES:-}
if [[ -z "$quota_free" ]] && command -v myquota >/dev/null; then
    quota_free=$(myquota | awk '$1 == "/scratch" {
        gsub(/GB/, "", $2); gsub(/GB/, "", $3)
        printf "%.0f", ($2 - $3) * 1000000000
    }')
fi
[[ "$quota_free" =~ ^[0-9]+$ ]] || {
    echo 'Set DEEP1B_QUOTA_FREE_BYTES from myquota.' >&2
    exit 2
}
physical_free=$(df -B1 --output=avail "$base" | tail -n 1)
available=$((quota_free < physical_free ? quota_free : physical_free))
read -r reserved required < <(python3 - "$suite" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1])))
from preflight_fullgraph import storage_plan

large = storage_plan(100_000_000, "full", 10**15,
                     rebuild_knn=True)["worst_case_bytes"]
medium = storage_plan(50_000_000, "full", 10**15)[
    "worst_case_bytes"]
peak = 4 * large + 2 * medium + 20_000_000_000
peak += 3 * 30_000_000_000  # CPU graph and clustering reserve.
peak += 200_000_000_000  # Two independent JSS campaign reserves.
print(peak, (peak * 20 + 16) // 17)
PY
)
if ((available < required)); then
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
ledger=$base/fastEmbedR-results/massive-data/deep1b_matrix/
ledger+=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$ledger"
print_plan > "$ledger/plan.tsv"
printf 'image_sha256=%s\nreserved_peak_bytes=%s\n' \
    "$digest" "$reserved" > "$ledger/identity.txt"
sha256sum "$suite/submit_matrix.sh" \
    "$suite/submit_fullgraph5m.sh" \
    "$suite/run_fullgraph_job.sh" \
    "$suite/run_full_graph.R" > "$ledger/source.sha256"
printf 'mode\trows\tlane\tjob\tcampaign\tdependency\n' \
    > "$ledger/jobs.tsv"

declare -A last_job job_for_case
submit_case() {
    local mode=$1 rows=$2 lane=$3 dependency=$4
    case_details "$lane"
    local output record job campaign
    output=$(DEEP1B_FIT_MODE="$mode" \
        DEEP1B_FULLGRAPH_ROWS="$rows" \
        DEEP1B_BACKEND_FILTER="$backend" \
        DEEP1B_CPU_CORES="$cores" \
        DEEP1B_GPU_DEVICES="$devices" \
        DEEP1B_AFTER_JOB="$dependency" \
        bash "$suite/submit_fullgraph5m.sh" deep)
    record=$(printf '%s\n' "$output" | awk -F '\t' \
        -v route="$backend" '$1 == "deep" && $2 == route')
    [[ -n "$record" ]] || { echo "$output" >&2; exit 1; }
    job=$(printf '%s\n' "$record" | cut -f 5)
    campaign=$(printf '%s\n' "$record" | cut -f 6)
    [[ "$job" =~ ^[0-9]+$ ]] || {
        echo "Submission blocked: $mode $rows $lane" >&2
        exit 3
    }
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$mode" "$rows" "$lane" "$job" "$campaign" \
        "${dependency:--}" >> "$ledger/jobs.tsv"
    if [[ "$mode" == full ]]; then
        last_job[$lane]=$job
        job_for_case["${lane}_${rows}"]=$job
    fi
}

submit_case classic 1000000 cpu4 ''
submit_case classic 1000000 cuda1 ''
for lane in "${lanes[@]}"; do
    for rows in "${rows_list[@]}"; do
        dependency=
        if ((rows >= 50000000)); then
            dependency=${last_job[$lane]:-}
        fi
        if [[ "$lane" == cpu16 && "$rows" == 100000000 ]]; then
            dependency+=:${job_for_case[cpu4_100000000]}
        fi
        if [[ "$lane" == cuda4 && "$rows" == 100000000 ]]; then
            dependency+=:${job_for_case[cuda2_100000000]}
        fi
        submit_case full "$rows" "$lane" "$dependency"
    done
done
printf 'Submitted Deep1B matrix: %s\n' "$ledger/jobs.tsv"
