#!/bin/bash
#SBATCH --job-name=fer-stage-535d071
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v1/stage-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v1/stage-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v1
archive="$root/plan.tar.gz"
[[ -r "$archive" && ! -e "$root/plan-summary.json" ]]
printf '%s  %s\n' \
    8d228eaaebec432bbda7da1e5248f357782277699168f7935cdd5584ec7631dd \
    "$archive" | sha256sum -c -
tar -xzf "$archive" -C "$root"
python3 - "$root" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
summary = json.loads((root / 'plan-summary.json').read_text())
cases = [json.loads(line) for line in
         (root / 'cases.jsonl').read_text().splitlines()]
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
assert summary['package_commit'] == \
    '535d071849945db3fa550d3c50f80633b91748cc'
assert summary['total_cases'] == 462 == len(cases)
assert summary['cores'] == [1, 2, 4, 8, 16, 32]
assert len({case['case_id'] for case in cases}) == 462
assert summary['scaling_cases_sha256'] == digest(root / 'cases.jsonl')
assert summary['staged_runner_sha256'] == digest(root / 'run_case.py')
assert summary['staged_worker_sha256'] == digest(root / 'matched_worker.R')
assert summary['source_routes_sha256'] == digest(root / 'routes.json')
assert all(case['storage_mode'] == 'in_memory' and
           case['runtime_input'] == 'resident' and
           case['algorithm_state'] == 'resident' and
           case['backend'] == 'cpu' and case['gpus'] == 0 and
           case['spill'] is False for case in cases)
for cores in summary['cores']:
    script = root / f'wave_cpu{cores}.sbatch'
    assert summary['wave_script_sha256'][str(cores)] == digest(script)
print('staged_cases=462 resident_only=true source=535d071')
PY
