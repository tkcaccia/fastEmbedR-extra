#!/bin/bash
#SBATCH --job-name=fer-stage-v3
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v3-stage-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v3-stage-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks
dest="$root/matched_main_535d071_20261107_v3"
archive="$root/matched_main_535d071_20261107_v3.tar.gz"
test ! -e "$dest"
test -f "$archive"
cd "$root"
tar -xzf "$archive"
python3 - <<'PY'
import hashlib
import json
from pathlib import Path
root = Path('/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3')
summary = json.loads((root / 'plan-summary.json').read_text())
assert summary['benchmark_source'] == 'matched-main-535d071-20261107-v3'
assert summary['package_commit'] == '535d071849945db3fa550d3c50f80633b91748cc'
assert summary['total_cases'] == 462
assert summary['storage_mode'] == 'in_memory' and summary['spill'] is False
for name, key in [('matched_worker.R', 'staged_worker_sha256'),
                  ('run_case.py', 'staged_runner_sha256'),
                  ('cases.jsonl', 'scaling_cases_sha256')]:
    observed = hashlib.sha256((root / name).read_bytes()).hexdigest()
    assert observed == summary[key], name
print('resident_v3_plan_staged 462 identity_verified')
PY
