#!/usr/bin/env bash
set -euo pipefail
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1
suite=${REAL_SUITE:?}
root=${REAL_ROOT:?}
dataset=${REAL_DATASET:?}
base=${REAL_BASE:?}
image=$base/singularity/fastembedr_cuda.sif
case_file=${REAL_CASE_FILE:?}
row=$(sed -n "$((SLURM_ARRAY_TASK_ID + 2))p" "$case_file")
test -n "$row"
IFS=$'\t' read -r name route backend cores devices mode rows \
    columns observed_dataset <<< "$row"
test "$dataset" = "$observed_dataset"
test "$cores" -le "${SLURM_CPUS_PER_TASK:-0}"
case "$name" in *[!a-zA-Z0-9_]*) exit 2 ;; esac
out=$root/$dataset/results/$name
mkdir -p "$out"
status() {
    code=$?
    printf 'case\troute\tbackend\tmode\texit_code\n' \
        > "$out/status.tsv"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$route" \
        "$backend" "$mode" "$code" >> "$out/status.tsv"
}
trap status EXIT
sha256sum -c "$root/source.sha256" > "$out/source_check.txt"
test "$(stat -Lc '%d:%i:%s:%Y:%Z' "$image")" = \
    "$(<"$root/image.stat")"
input=$root/$dataset/input/input.f32
test "$(stat -Lc %s "$input")" -eq "$((rows * columns * 4))"
test "$(stat -Lc '%d:%i:%s:%Y:%Z' "$input")" = \
    "$(<"$root/$dataset/input/input.stat")"
output=$out/output.f32
if [[ "$mode" == cluster ]]; then output=$out/output; fi
if [[ "$route" == classic ]]; then
    cmd=(/opt/r46/bin/Rscript "$suite/run_classic.R" \
         "$input" "$rows" "$columns" "$mode" "$backend" \
         "$cores" "$output")
else
    cmd=(/opt/r46/bin/Rscript \
        "$base/benchmark_scripts/massive-data/run_scaling.R" \
        --input "$input" --rows "$rows" --columns "$columns" \
        --backend "$backend" --mode "$mode" --output "$output" \
        --csv "$out/metrics.csv" --save-model false \
        --expected-version 0.1 --n-cores "$cores" \
        --components 2 --neighbors 30 --landmarks 20000 \
        --seed 4 --chunk-rows 10000 --memory-limit 4GB \
        --perplexity 30 --transform-iter 250 \
        --early-iterations 250 --normal-iterations 750)
    if [[ "$devices" != - ]]; then cmd+=(--devices "$devices"); fi
    if [[ "$mode" == cluster ]]; then
        cmd+=(--cluster-method leiden)
    fi
fi
if [[ "$backend" == cuda ]]; then nv=(--nv); else nv=(); fi
set +e
/usr/bin/time -v -o "$out/time.txt" \
    timeout --signal=TERM 7200 \
    singularity exec "${nv[@]}" "$image" "${cmd[@]}" \
    > "$out/fit.out" 2> "$out/fit.err" &
pid=$!
monitor=
if [[ "$backend" == cuda ]]; then
    python3 "$base/benchmark_scripts/massive-data/deep1b/gpu_memory.py" \
        "$pid" "$out/gpu_memory.csv" &
    monitor=$!
fi
wait "$pid"
code=$?
if [[ -n "$monitor" ]]; then
    wait "$monitor"
    monitor_code=$?
    if [[ "$code" -eq 0 && "$monitor_code" -ne 0 ]]; then
        code=$monitor_code
    fi
fi
set -e
if [[ "$code" -ne 0 ]]; then exit "$code"; fi
if [[ "$route" == classic ]]; then
    cp "$out/output.metrics.csv" "$out/metrics.csv"
fi
if [[ "$mode" != cluster ]]; then
    singularity exec "$image" /opt/r46/bin/Rscript \
        "$suite/render_and_score.R" "$input" "$output" \
        "$rows" "$columns" "$out" \
        > "$out/score.out" 2> "$out/score.err"
fi
