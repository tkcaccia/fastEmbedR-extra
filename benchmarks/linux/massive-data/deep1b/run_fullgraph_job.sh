#!/usr/bin/env bash
set -euo pipefail
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data
root=${DEEP1B_FULLGRAPH_ROOT:?Set DEEP1B_FULLGRAPH_ROOT}
dataset=${BIGANN_DATASET:?Set BIGANN_DATASET}
backend=${DEEP1B_BACKEND:?Set DEEP1B_BACKEND}
rows=${DEEP1B_FULLGRAPH_ROWS:-5000000}
mode=${DEEP1B_FIT_MODE:-full}
default_rebuild=0
if [[ "$mode" == full && "$rows" -ge 100000000 ]]; then
    default_rebuild=1
fi
rebuild_knn=${DEEP1B_REBUILD_KNN_FOR_UMAP:-$default_rebuild}
image=$root/image.sif
input=$base/Data/BigANN/$dataset/1000000000/base.1000000000.fbin
nv=()
if [[ "$backend" == cuda ]]; then nv=(--nv); fi
label=fullgraph
runner=run_full_graph.R
methods=(pca tsne umap leiden louvain)
if [[ "$mode" == classic ]]; then
    label=classic
    runner=run_classic_1m.R
elif [[ "$mode" == pca ]]; then
    methods=(pca)
elif [[ "$mode" == full_tsne ]]; then
    methods=(pca tsne)
elif [[ "$mode" == full_umap ]]; then
    methods=(pca umap leiden louvain)
fi
if [[ "$backend" == cuda &&
      "${DEEP1B_GPU_DEVICES:-}" != *,* ]]; then
    filtered=()
    for method in "${methods[@]}"; do
        if [[ "$method" != leiden && "$method" != louvain ]]; then
            filtered+=("$method")
        fi
    done
    methods=("${filtered[@]}")
fi
case_name() { printf '%s_%s_%s_%s' \
    "$backend" "$1" "$rows" "$label"; }
write_pass_audit() {
    python3 - "$root/audit.json" "$root/knn.csv" \
        "$root/knn_rebuild.csv" \
        "$rebuild_knn" "$mode" \
        "$root/unsupported_methods.tsv" <<'PY'
import csv
import json
import sys
from pathlib import Path

audit, knn, rebuilt = map(Path, sys.argv[1:4])
rebuild_requested = sys.argv[4] == "1"
mode = sys.argv[5]
unsupported_path = Path(sys.argv[6])
warnings = []
unsupported = []
if mode not in ("pca", "classic") and not knn.exists():
    raise SystemExit("Initial KNN recall record is missing")
if rebuild_requested and not rebuilt.exists():
    raise SystemExit("Rebuilt KNN recall record is missing")
for path in (knn, rebuilt if rebuild_requested else None):
    if path is None or not path.exists():
        continue
    with path.open(newline="") as stream:
        row = next(csv.DictReader(stream))
    if row["sample_target_met"] != "TRUE":
        warnings.append(path.name + ": sampled recall below 0.99")
if unsupported_path.exists():
    with unsupported_path.open(newline="") as stream:
        unsupported = list(csv.DictReader(stream, delimiter="\t"))
audit.write_text(json.dumps({"status": "PASS", "failures": [],
                             "warnings": warnings,
                             "unsupported_methods": unsupported}) + "\n")
PY
}
prune_work() {
    printf 'path\tbytes\n' > "$root/pruned_payloads.tsv"
    [[ -d "$root/work" ]] || return 0
    while IFS= read -r -d '' path; do
        printf '%s\t%s\n' "${path#"$root"/}" \
            "$(stat -c %s "$path")" >> "$root/pruned_payloads.tsv"
        rm -- "$path"
    done < <(find "$root/work" -type f \
        ! -name '*_labels.u32' -print0)
}
on_error() {
    code=$?
    printf '{"status":"FAIL","exit_code":%s,' "$code" \
        > "$root/audit.json"
    printf '"failures":["Worker failed before final audit"]}\n' \
        >> "$root/audit.json"
    exit "$code"
}
trap on_error ERR
test -s "$input"
sha256sum -c "$root/source.sha256" > "$root/source_check.txt"
sha256sum -c "$root/image.sha256" >> "$root/source_check.txt"

set +e
/usr/bin/time -v -o "$root/time.txt" \
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
    "$suite/deep1b/$runner" \
    "$input" "$dataset" "$backend" "$rows" "$root" \
    > "$root/fit.out" 2> "$root/fit.err" &
fit_pid=$!
python3 "$suite/deep1b/disk_peak.py" "$fit_pid" "$root" \
    "$root/disk_peak.csv" &
disk_pid=$!
monitor_pid=
if [[ "$backend" == cuda ]]; then
    python3 "$suite/deep1b/gpu_memory.py" "$fit_pid" \
        "$root/gpu_memory.csv" &
    monitor_pid=$!
fi
wait "$fit_pid"
code=$?
wait "$disk_pid"
disk_code=$?
if [[ "$code" == 0 && "$disk_code" != 0 ]]; then
    code=$disk_code
fi
if [[ -n "$monitor_pid" ]]; then
    wait "$monitor_pid"
    monitor_code=$?
    if [[ "$code" == 0 && "$monitor_code" != 0 ]]; then
        code=$monitor_code
    fi
fi
set -e
if [[ "$backend" == cuda && "$code" == 0 ]]; then
    if [[ "$mode" == classic ]]; then
        if ! python3 - "$root/gpu_memory.csv" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="") as stream:
    row = next(csv.DictReader(stream))
if row["status"] != "ok" or int(row["device_count"]) != 1:
    raise SystemExit("Classic GPU memory sampling was incomplete")
PY
        then
            code=1
        fi
    elif ! python3 "$suite/deep1b/gpu_memory.py" --verify \
        "$root/gpu_memory.csv" "$root/gpu_device_map.csv"; then
        code=1
    fi
fi
missing=()
for method in "${methods[@]}"; do
    name=$(case_name "$method")
    out=$root/results/$name
    output=$out/output.f32
    if [[ "$method" == leiden || "$method" == louvain ]]; then
        output=$root/work/${method}_labels.u32
    fi
    if [[ ! -s "$out/metrics.csv" || ! -s "$output" ]]; then
        missing+=("$method")
        continue
    fi
    if [[ "$method" == leiden || "$method" == louvain ]]; then
        singularity exec "$image" /opt/r46/bin/Rscript \
            "$suite/deep1b/score_fullgraph_leiden.R" "$output" \
            "$rows" "$out" "$root/figures/$name.png" \
            > "$out/score.out" 2> "$out/score.err"
        test -s "$root/figures/$name.png"
        continue
    fi
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
        "$suite/deep1b/score.R" "$input" "$output" \
        "$rows" 2 "$out" "$dataset" "${DEEP1B_FIRST_ROW:-1000001}" \
        > "$out/score.out" 2> "$out/score.err"
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
        "$suite/visualization/render_full_layouts.R" \
        "$base" "$dataset" "$rows" "$root/figures" \
        "$root" "$name" > "$out/plot.out" 2> "$out/plot.err"
    test -s "$root/figures/$name.png"
done
if [[ "$code" == 0 && ${#missing[@]} == 0 && \
      ( "$mode" == classic || "$mode" == full ) ]]; then
    write_pass_audit
    singularity exec "${nv[@]}" "$image" /opt/r46/bin/Rscript \
        "$suite/visualization/render_full_layouts.R" \
        "$base" "$dataset" "$rows" "$root/figures" "$root" \
        > "$root/plot.out" 2> "$root/plot.err"
    test -s "$root/figures/${dataset}_${backend}_${rows}_comparison.png"
fi
if [[ "$code" == 0 && ${#missing[@]} == 0 ]]; then
    write_pass_audit
else
    python3 - "$root/audit.json" "$code" "${missing[@]}" <<'PY'
import json
import sys

path, code, *missing = sys.argv[1:]
failures = [f"{method}: no complete fit" for method in missing]
if int(code):
    failures.append(f"fit process exited {code}")
with open(path, "w", encoding="utf-8") as stream:
    json.dump(dict(status="FAIL", fit_exit_code=int(code),
                   failures=failures), stream)
    stream.write("\n")
PY
fi
trap - ERR
if [[ "$code" != 0 || ${#missing[@]} != 0 ]]; then exit 1; fi
prune_work
echo "$mode results and all-row PNGs: $root"
