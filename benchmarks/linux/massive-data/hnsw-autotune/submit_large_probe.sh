#!/usr/bin/env bash
# Selected settings only; sampled-query recall, not an all-row graph.
set -euo pipefail

[[ $# -eq 1 ]] || {
    echo 'Usage: submit_large_probe.sh REPRESENTATIVE_CAMPAIGN' >&2
    exit 2
}
representative=$(realpath "$1")
base=${HNSW_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/hnsw-autotune
image=${HNSW_IMAGE:-$base/singularity/fastembedr_cuda.sif}
data_root=${BIGANN_DATA_ROOT:-$base/Data/BigANN}
parent=$base/fastEmbedR-results/massive-data/hnsw-autotune
account=${HNSW_ACCOUNT:-immunology}
partition=${HNSW_PARTITION:-ada}
python3 - "$representative" "$image" <<'PY'
import csv, hashlib, json, sys
from pathlib import Path
root, image = map(Path, sys.argv[1:])
audit = json.loads((root / 'audit_representative.json').read_text())
if not audit.get('complete'):
    raise SystemExit('Representative pilot did not pass structural audit')
selected = list(csv.DictReader((root / 'selected.csv').open()))
if not any(row['shard_rows'] == '250000' for row in selected):
    raise SystemExit('No calibrated 250k-shard candidate')
expected = (root / 'source.sha256').read_text().split()[0]
h = hashlib.sha256()
with image.open('rb') as stream:
    for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
        h.update(block)
if h.hexdigest() != expected:
    raise SystemExit('SIF changed after calibration')
PY
files=(make_cases.py make_cases_large_probe.py worker.R worker.sbatch
    preflight_5m.R audit.py audit_5m.py audit_large_probe.py
    submit_large_probe.sh)
paths=()
for file in "${files[@]}"; do
    test -s "$suite/$file"
    paths+=("$suite/$file")
done
mkdir -p "$parent" "$base/benchmark_logs"
root=$(mktemp -d "$parent/$(date -u +%Y%m%dT%H%M%SZ)_large_XXXXXX")
rmdir "$root"
python3 "$suite/make_cases_large_probe.py" "$root" \
    "$representative" "$data_root"
touch "$root/preflight.required"
sha256sum "$image" "${paths[@]}" > "$root/source.sha256"
sha256sum "${paths[@]}" > "$root/code.sha256"
printf 'stage\tjob_id\tcase_count\n' > "$root/jobs.tsv"
common=(--parsable --account="$account" --partition="$partition"
    --chdir="$base" --output="$base/benchmark_logs/feR_hnsw_%A_%a.out"
    --error="$base/benchmark_logs/feR_hnsw_%A_%a.err")
exported="ALL,HNSW_SUITE=$suite,HNSW_ROOT=$root,HNSW_IMAGE=$image"
exported+=",BIGANN_DATA_ROOT=$data_root"
preflight=$(sbatch "${common[@]}" --job-name=feR_hnsw_preflight
    --cpus-per-task=1 --mem=2G --time=00:20:00
    --export="$exported,HNSW_PHASE=preflight_5m" "$suite/worker.sbatch")
printf 'preflight\t%s\t1\n' "$preflight" >> "$root/jobs.tsv"
count=$(($(wc -l < "$root/truth_cases.tsv") - 1))
sweeps=()
for ((index=0; index<count; index++)); do
    truth=$(sbatch "${common[@]}" --job-name=feR_hnsw_large_truth
        --dependency="afterok:$preflight" --array="$index"
        --cpus-per-task=8 --mem=24G --time=2-00:00:00
        --export="$exported,HNSW_PHASE=truth" "$suite/worker.sbatch")
    sweep=$(sbatch "${common[@]}" --job-name=feR_hnsw_large_sweep
        --dependency="afterok:$truth" --array="$index"
        --cpus-per-task=4 --mem=24G --time=2-00:00:00
        --export="$exported,HNSW_PHASE=sweep" "$suite/worker.sbatch")
    printf 'truth_%s\t%s\t1\n' "$index" "$truth" >> "$root/jobs.tsv"
    printf 'sweep_%s\t%s\t1\n' "$index" "$sweep" >> "$root/jobs.tsv"
    sweeps+=("$sweep")
done
dependency=$(IFS=:; echo "${sweeps[*]}")
audit=$(sbatch "${common[@]}" --job-name=feR_hnsw_large_audit
    --dependency="afterany:$dependency" --cpus-per-task=1
    --mem=4G --time=00:30:00
    --export="$exported,HNSW_PHASE=audit_large_probe"
    "$suite/worker.sbatch")
printf 'audit\t%s\t1\n' "$audit" >> "$root/jobs.tsv"
printf 'Campaign: %s\nAudit job: %s\n' "$root" "$audit"
