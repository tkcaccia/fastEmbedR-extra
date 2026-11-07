#!/usr/bin/env python3
"""Run the reviewed resident Mac panel serially with pressure stops."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
LOG = ROOT / 'queue-status.jsonl'

def record(**fields):
    with LOG.open('a') as stream:
        stream.write(json.dumps({'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ',
            time.gmtime()), **fields}, sort_keys=True) + '\n')
        stream.flush()
        os.fsync(stream.fileno())

def swap_mib():
    text = subprocess.run(['sysctl', 'vm.swapusage'], check=True,
        capture_output=True, text=True, timeout=5).stdout
    match = re.search(r'used = ([0-9.]+)([MG])', text)
    if not match:
        raise RuntimeError('Cannot measure system swap')
    return float(match.group(1)) * (1024 if match.group(2) == 'G' else 1)

def main():
    lock = ROOT / 'queue.lock'
    with lock.open('x') as stream:
        stream.write(str(os.getpid()) + '\n')
    initial_swap = swap_mib()
    record(event='started', pid=os.getpid(), baseline_swap_mib=initial_swap)
    failures = 0
    for index, name in enumerate((ROOT / 'queue.txt').read_text().splitlines(), 1):
        manifest = ROOT / 'manifests' / name
        case = json.loads(manifest.read_text())
        if not manifest.is_file() or not (ROOT / 'run_case.py').is_file():
            raise RuntimeError('Missing immutable case or runner')
        if shutil.disk_usage(ROOT).free < 100 * 1024 ** 3:
            record(event='stopped', reason='disk_floor', index=index)
            return 2
        current_swap = swap_mib()
        if current_swap - initial_swap > 1024:
            record(event='stopped', reason='swap_growth', index=index,
                   swap_mib=current_swap)
            return 2
        record(event='case_started', index=index, case_id=case['case_id'])
        with (ROOT / 'queue-worker.log').open('a') as log:
            status = subprocess.run(['/usr/bin/python3', str(ROOT / 'run_case.py'),
                str(manifest)], cwd=ROOT, stdout=log,
                stderr=subprocess.STDOUT, check=False).returncode
        run_file = Path(case['output_dir']) / 'run.json'
        run = json.loads(run_file.read_text()) if run_file.is_file() else {}
        record(event='case_finished', index=index, case_id=case['case_id'],
               exit_code=status, status=run.get('status'),
               cleanup_clear=run.get('cleanup_clear'))
        if not run.get('cleanup_clear') or run.get('timed_out'):
            record(event='stopped', reason='cleanup_or_timeout', index=index)
            return 2
        failures = failures + 1 if status else 0
        if failures >= 3:
            record(event='stopped', reason='three_consecutive_failures',
                   index=index)
            return 2
    record(event='completed', cases=index)
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        record(event='failed', error=repr(error))
        raise
