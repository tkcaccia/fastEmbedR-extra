#!/usr/bin/env bash

set -euo pipefail
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data
lane=${DEEP1B_SUITE:-$suite/deep1b}
runner=${DEEP1B_RUNNER:-$suite/run_scaling.R}
dataset=${BIGANN_DATASET:-deep}
case "$dataset" in
    deep) columns=96 ;;
    turing) columns=100 ;;
    *) echo "Unsupported BigANN dataset: $dataset" >&2; exit 2 ;;
esac
default_input=$base/Data/BigANN/$dataset/1000000000/base.1000000000.fbin
input=${DEEP1B_INPUT:-$default_input}
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
first_row=${DEEP1B_FIRST_ROW:-1}
root=${DEEP1B_CAMPAIGN:?Set DEEP1B_CAMPAIGN}
index=${SLURM_ARRAY_TASK_ID:?Run as a Slurm array task}
case_file=${DEEP1B_CASE_FILE:?Set DEEP1B_CASE_FILE}
row=$(sed -n "$((index + 2))p" "$case_file")
[[ -n "$row" ]] || { echo "No case at index $index" >&2; exit 2; }
IFS=$'\t' read -r name phase backend mode rows cores components \
    landmarks neighbors devices cluster_method <<< "$row"
[[ "$backend" == cpu || "$backend" == cuda ]] || exit 2
[[ "$first_row" =~ ^[0-9]+$ && "$first_row" -ge 1 ]] || exit 2
[[ "$cores" -le "${SLURM_CPUS_PER_TASK:-0}" ]] || {
    echo "Case asks for $cores CPU workers but Slurm allocated fewer." >&2
    exit 2
}
[[ "$name" =~ ^[a-z0-9_]+$ ]] || exit 2
[[ "$phase" == "$DEEP1B_PHASE" ]] || exit 2
[[ "$backend" == "$DEEP1B_BACKEND" ]] || exit 2
out=$root/results/$name
mkdir -p "$out"
output=$out/output
if [[ "$mode" != knn && "$mode" != cluster ]]; then
    output=$out/output.f32
fi
prune_payloads() {
    printf 'path\tbytes\n' > "$out/pruned_payloads.tsv"
    for path in "$out"/output.knn.indices.u32* \
                "$out"/output.knn.distances.f32* \
                "$out"/output.clusters.u32* \
                "$out"/output.confidence.f32* \
                "$out"/output.f32*; do
        [[ -f "$path" && ! -L "$path" ]] || continue
        printf '%s\t%s\n' "${path##*/}" "$(stat -c %s "$path")" \
            >> "$out/pruned_payloads.tsv"
        rm -- "$path"
    done
}
write_status() {
    code=$?
    printf 'case\tphase\tbackend\tmode\texit_code\n' > "$out/status.tsv"
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$phase" "$backend" "$mode" "$code" \
        >> "$out/status.tsv"
    if [[ "$code" != 0 && "$phase" == billion && \
          "${DEEP1B_PRUNE_BILLION:-0}" == 1 ]]; then
        prune_payloads
    fi
}
trap write_status EXIT
[[ -f "$root/preflight.ok" ]] || {
    echo "Compute-node preflight did not pass." >&2
    exit 1
}
sha256sum -c "$root/source.sha256" > "$out/source_check.txt"
[[ "$(stat -Lc '%i:%s:%Y' "$image")" == \
   "$(<"$root/image.stat")" ]] || {
    echo "Image changed after the stage preflight." >&2
    exit 1
}
printf 'image metadata: OK\n' >> "$out/source_check.txt"
python3 "$lane/validate_input.py" "$input" \
    --dataset "$dataset" > "$out/input.json"
cp "$root/image.sha256" "$out/code_image.sha256"
sha256sum "$runner" "$case_file" \
    >> "$out/code_image.sha256"
printf 'job=%s node=%s dataset=%s backend=%s mode=%s first_row=%s\n' \
    "$SLURM_JOB_ID" "$(hostname)" "$dataset" \
    "$backend" "$mode" "$first_row" > "$out/job.txt"

# Include all-row KNN sidecars, not just the final coordinates.
if [[ "$mode" == knn ]]; then
    output_bytes=$((rows * neighbors * 8))
elif [[ "$mode" == cluster ]]; then
    output_bytes=$((rows * (neighbors * 8 + 8) + landmarks * columns * 4))
elif [[ "$mode" == umap || "$mode" == tsne ]]; then
    output_bytes=$((rows * (neighbors * 8 + components * 4) +
                    landmarks * columns * 4))
else
    output_bytes=$((rows * components * 4))
fi
if [[ "$phase" == billion ]]; then
    free_gb=${DEEP1B_SCRATCH_FREE_GB:-}
    [[ "$free_gb" =~ ^[0-9]+$ && "$free_gb" -ge 600 ]] || {
        echo "Billion-row job needs a submission-time scratch quota" \
            "reading of at least 600 GB; got ${free_gb:-none}." >&2
        exit 1
    }
    printf 'scratch_quota_free_gb_at_submission=%s\n' "$free_gb" \
        >> "$out/job.txt"
fi
available=$(df -B1 --output=avail "$out" | tail -n 1)
multiplier=3
if [[ "$phase" == billion && \
      "${DEEP1B_PRUNE_BILLION:-0}" == 1 ]]; then
    multiplier=2
fi
required=$((output_bytes * multiplier + 21474836480))
[[ "$available" -ge "$required" ]] || {
    echo "Insufficient output space for $name: need at least" \
        "$required bytes; have $available" >&2
    exit 1
}

cmd=(/opt/r46/bin/Rscript "$runner"
    --input "$input" --rows "$rows" --first-row "$first_row"
    --columns "$columns"
    --backend "$backend" --mode "$mode"
    --output "$output" --csv "$out/metrics.csv"
    --save-model false
    --expected-version "${FASTEMBEDR_EXPECTED_VERSION:-0.1}"
    --n-cores "$cores" --components "$components"
    --landmarks "$landmarks" --neighbors "$neighbors"
    --perplexity 30 --seed 4 --chunk-rows 10000
    --memory-limit 4GB --transform-iter 250
    --early-iterations 250 --normal-iterations 750)
if [[ "$mode" == cluster ]]; then
    [[ "$cluster_method" == leiden ||
       "$cluster_method" == louvain ||
       "$cluster_method" == walktrap ]] || {
        echo "Invalid cluster method: $cluster_method" >&2
        exit 2
    }
    cmd+=(--cluster-method "$cluster_method")
fi
if [[ "$mode" == knn ]]; then
    reference_rows=20000
    audit_rows=16
    if [[ "$DEEP1B_PHASE" == fresh5m_graph ||
          "$DEEP1B_PHASE" == graph10m ||
          "$DEEP1B_PHASE" == threads1m ]]; then
        reference_rows=50000
        audit_rows=128
    fi
    if [[ "$DEEP1B_PHASE" == graph10m ]]; then
        audit_rows=1024
    fi
    cmd+=(--reference-chunk-rows "$reference_rows"
        --audit-rows "$audit_rows")
    if [[ -n "${DEEP1B_HNSW_M:-}" ||
          -n "${DEEP1B_HNSW_EFC:-}" ||
          -n "${DEEP1B_HNSW_EFS:-}" ]]; then
        [[ "$backend" == cpu && -n "${DEEP1B_HNSW_M:-}" &&
           -n "${DEEP1B_HNSW_EFC:-}" &&
           -n "${DEEP1B_HNSW_EFS:-}" ]] || {
            echo "Explicit HNSW settings need CPU and all three values." >&2
            exit 2
        }
        cmd+=(--hnsw-m "$DEEP1B_HNSW_M"
            --hnsw-ef-construction "$DEEP1B_HNSW_EFC"
            --hnsw-ef-search "$DEEP1B_HNSW_EFS")
    fi
fi
if [[ -n "${FASTEMBEDR_EXPECTED_DLL_SHA256:-}" ]]; then
    cmd+=(--expected-dll-sha256 "$FASTEMBEDR_EXPECTED_DLL_SHA256")
fi
if [[ "$devices" != - ]]; then cmd+=(--devices "$devices"); fi
if [[ "$backend" == cuda ]]; then nv=(--nv); else nv=(); fi
set +e
/usr/bin/time -v -o "$out/time.txt" \
    singularity exec "${nv[@]}" "$image" "${cmd[@]}" \
    > "$out/fit.out" 2> "$out/fit.err" &
fit_pid=$!
monitor_pid=
if [[ "$backend" == cuda ]]; then
    python3 "$lane/gpu_memory.py" "$fit_pid" \
        "$out/gpu_memory.csv" &
    monitor_pid=$!
fi
wait "$fit_pid"
code=$?
if [[ -n "$monitor_pid" ]]; then
    wait "$monitor_pid"
    monitor_code=$?
    if [[ "$code" == 0 && "$monitor_code" != 0 ]]; then
        code=$monitor_code
    fi
fi
set -e
[[ "$code" == 0 ]] || exit "$code"
if [[ "$mode" == cluster ]]; then
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
        "$lane/score_cluster.R" "$output" "$rows" "$out" \
        "$first_row" \
        > "$out/score.out" 2> "$out/score.err"
elif [[ "$mode" != knn ]]; then
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
        "$lane/score.R" "$input" "$output" \
        "$rows" "$components" "$out" "$dataset" "$first_row" \
        > "$out/score.out" 2> "$out/score.err"
elif [[ "$DEEP1B_PHASE" == fresh5m_graph ]]; then
    truth=${DEEP1B_TRUTH_CAMPAIGN:?Set DEEP1B_TRUTH_CAMPAIGN}
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
        "$lane/score_knn_exact.R" "$output" \
        "$truth/truth/${dataset}_fresh5m.rds" "$input" \
        "$first_row" "$rows" "$neighbors" \
        "$out/knn_exact_quality.csv" \
        > "$out/knn_score.out" 2> "$out/knn_score.err"
fi
if [[ "$mode" == pca || "$mode" == umap || "$mode" == tsne ]] && \
    [[ "$phase" == fresh5m || "$phase" == fresh5m_3d || \
       "$phase" == scale10m || "$phase" == boundary || \
       "$phase" == billion ]]; then
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
        "$suite/visualization/render_full_layouts.R" \
        "$base" "$dataset" "$rows" "$out/figures" \
        "$root" "$name" \
        > "$out/plot.out" 2> "$out/plot.err"
    if [[ "$components" == 2 ]]; then
        test -s "$out/figures/$name.png"
    else
        test -s "$out/figures/${name}_xy.png"
    fi
fi
if [[ "$phase" == billion && "${DEEP1B_PRUNE_BILLION:-0}" == 1 ]]; then
    prune_payloads
fi
