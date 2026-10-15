#!/usr/bin/env bash
set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data
root=${DEEP1B_RETRY_ROOT:?Set DEEP1B_RETRY_ROOT}
image=$root/image.sif
input=$base/Data/BigANN/deep/1000000000/base.1000000000.fbin
case_dir=$root/results/cuda_pca_20000000_fullgraph
output=$case_dir/output.f32
mkdir -p "$case_dir" "$root/figures"
trap 'rm -f -- "$image"' EXIT
sha256sum -c "$root/source.sha256" > "$root/source_check.txt"
sha256sum -c "$root/image.sha256" >> "$root/source_check.txt"

export DEEP1B_FIT_MODE=pca DEEP1B_FIRST_ROW=1000001
export DEEP1B_MEMORY_LIMIT=8GB DEEP1B_GPU_DEVICES=0,1
export DEEP1B_CPU_CORES=1 DEEP1B_SMOKE=0
singularity exec --nv "$image" /opt/r46/bin/Rscript -e \
    'stopifnot(utils::packageVersion("gpuinfo") >= "0.2.0");
     cat(gpuinfo::hardware_manifest(memory="none", as="json"))' \
    > "$root/hardware_manifest.json"
fit_code=0
python3 "$suite/deep1b/gpu_memory_allocated.py" "$root" -- \
    /usr/bin/time -v -o "$root/time.txt" \
    singularity exec --nv "$image" /opt/r46/bin/Rscript \
    "$suite/deep1b/run_full_graph.R" \
    "$input" deep cuda 20000000 "$root" || fit_code=$?
printf '%s\n' "$fit_code" > "$root/fit.exit"

if [[ -s "$output" && -s "$case_dir/metrics.csv" ]]; then
    if singularity exec --nv "$image" /opt/r46/bin/Rscript \
        "$suite/deep1b/verify_retry_pca_2gpu.R" "$root" \
        > "$root/verify.out" 2> "$root/verify.err"; then
        touch "$root/verify.ok"
    fi
fi
if [[ -f "$root/verify.ok" ]]; then
    if singularity exec --nv "$image" /opt/r46/bin/Rscript \
        "$suite/deep1b/score.R" "$input" "$output" 20000000 2 \
        "$case_dir" deep 1000001 \
        > "$case_dir/score.out" 2> "$case_dir/score.err"; then
        touch "$root/score.ok"
    fi
fi
if [[ -f "$root/score.ok" ]]; then
    if singularity exec --nv "$image" /opt/r46/bin/Rscript \
        "$suite/visualization/render_full_layouts.R" \
        "$base" deep 20000000 "$root/figures" "$root" \
        cuda_pca_20000000_fullgraph \
        > "$case_dir/plot.out" 2> "$case_dir/plot.err"; then
        touch "$root/plot.ok"
    fi
fi

python3 - "$root" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
summary_path = root / "gpu_summary.json"
summary = json.loads(summary_path.read_text()) if summary_path.exists() else {}
failures = []
if int((root / "fit.exit").read_text()) != 0:
    failures.append("PCA fit or device monitor exited nonzero")
if summary.get("status") != "two_devices_active":
    failures.append("Both allocated GPUs were not observed above baseline")
for step in ("verify", "score", "plot"):
    if not (root / f"{step}.ok").exists():
        failures.append(f"{step} did not pass")
figure = root / "figures/cuda_pca_20000000_fullgraph.png"
if not figure.is_file() or figure.stat().st_size == 0:
    failures.append("Full-row PCA figure missing")
audit = {"status": "FAIL" if failures else "PASS",
         "failures": failures, "gpu_summary": summary}
(root / "audit.json").write_text(json.dumps(audit, sort_keys=True) + "\n")
if failures:
    print("; ".join(failures), file=sys.stderr)
    sys.exit(1)
PY

printf 'path\tbytes\n' > "$root/pruned_payloads.tsv"
find "$case_dir" -maxdepth 1 -type f -name 'output*' -print0 |
    while IFS= read -r -d '' path; do
        printf '%s\t%s\n' "${path#"$root"/}" \
            "$(stat -c %s "$path")" >> "$root/pruned_payloads.tsv"
        rm -- "$path"
    done
echo "Two-GPU PCA retry passed: $root"
