#!/usr/bin/env bash

set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data
lane=$suite/deep1b
dataset=${BIGANN_DATASET:-deep}
case "$dataset" in
    deep) columns=96 ;;
    turing) columns=100 ;;
    *) echo "Unsupported BigANN dataset: $dataset" >&2; exit 2 ;;
esac
default_input=$base/Data/BigANN/$dataset/1000000000/base.1000000000.fbin
input=${DEEP1B_INPUT:-$default_input}
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
root=${DEEP1B_CAMPAIGN:?Set DEEP1B_CAMPAIGN}
index=${SLURM_ARRAY_TASK_ID:?Run as a Slurm array task}
case_file=${DEEP1B_CASE_FILE:?Set DEEP1B_CASE_FILE}
row=$(sed -n "$((index + 2))p" "$case_file")
[[ -n "$row" ]] || { echo "No case at index $index" >&2; exit 2; }
IFS=$'\t' read -r name phase backend mode rows cores components \
    landmarks neighbors devices <<< "$row"
[[ "$backend" == cpu || "$backend" == cuda ]] || exit 2
[[ "$name" =~ ^[a-z0-9_]+$ ]] || exit 2
[[ "$phase" == "$DEEP1B_PHASE" ]] || exit 2
[[ "$backend" == "$DEEP1B_BACKEND" ]] || exit 2
out=$root/results/$name
mkdir -p "$out"
output=$out/output
if [[ "$mode" != knn ]]; then
    output=$out/output.f32
fi
write_status() {
    code=$?
    printf 'case\tphase\tbackend\tmode\texit_code\n' > "$out/status.tsv"
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$phase" "$backend" "$mode" "$code" \
        >> "$out/status.tsv"
}
trap write_status EXIT
python3 "$lane/validate_input.py" "$input" \
    --dataset "$dataset" > "$out/input.json"
sha256sum "$image" "$suite/run_scaling.R" "$case_file" \
    > "$out/code_image.sha256"
printf 'job=%s node=%s dataset=%s backend=%s mode=%s\n' \
    "$SLURM_JOB_ID" "$(hostname)" "$dataset" \
    "$backend" "$mode" > "$out/job.txt"

# Refuse a case whose projected output cannot leave 20 GiB free.
if [[ "$mode" == knn ]]; then
    output_bytes=$((rows * neighbors * 8))
else
    output_bytes=$((rows * components * 4))
fi
available=$(df -B1 --output=avail "$out" | tail -n 1)
[[ "$available" -ge $((output_bytes * 3 + 21474836480)) ]] || {
    echo "Insufficient output space for $name" >&2
    exit 1
}

cmd=(/opt/r46/bin/Rscript "$suite/run_scaling.R"
    --input "$input" --rows "$rows" --columns "$columns"
    --backend "$backend" --mode "$mode"
    --output "$output" --csv "$out/metrics.csv"
    --expected-version "${FASTEMBEDR_EXPECTED_VERSION:-0.1}"
    --n-cores "$cores" --components "$components"
    --landmarks "$landmarks" --neighbors "$neighbors"
    --perplexity 30 --seed 4 --chunk-rows 10000
    --memory-limit 4GB --transform-iter 250
    --early-iterations 250 --normal-iterations 750)
if [[ "$mode" == knn ]]; then
    cmd+=(--reference-chunk-rows 20000 --audit-rows 16)
fi
if [[ -n "${FASTEMBEDR_EXPECTED_DLL_SHA256:-}" ]]; then
    cmd+=(--expected-dll-sha256 "$FASTEMBEDR_EXPECTED_DLL_SHA256")
fi
if [[ "$devices" != - ]]; then cmd+=(--devices "$devices"); fi
if [[ "$backend" == cuda ]]; then nv=(--nv); else nv=(); fi
set +e
/usr/bin/time -v -o "$out/time.txt" \
    singularity exec "${nv[@]}" "$image" "${cmd[@]}" \
    > "$out/fit.out" 2> "$out/fit.err"
code=$?
set -e
[[ "$code" == 0 ]] || exit "$code"
if [[ "$mode" != knn ]]; then
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
        "$lane/score.R" "$input" "$output.model.rds" \
        "$rows" "$out" "$dataset" \
        > "$out/score.out" 2> "$out/score.err"
fi
