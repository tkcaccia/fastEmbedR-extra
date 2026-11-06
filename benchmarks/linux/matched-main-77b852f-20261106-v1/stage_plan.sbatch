#!/bin/bash
#SBATCH --job-name=fer-stage-77b852f
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_main_77b852f_20261106_v1/stage-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_main_77b852f_20261106_v1/stage-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_77b852f_20261106_v1
archive="$root/plan.tar.gz"
[[ -r "$archive" && ! -e "$root/plan-summary.json" ]]
printf '%s  %s\n' \
    387408f6d2c55e6ae4d61573b46bc18b5f6581eec0be2cb17a71f35c9dce01e7 \
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
    '77b852fc496ad4665969c4f6771088f5b98da4fe'
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
print('staged_cases=462 resident_only=true source=77b852f')
PY
