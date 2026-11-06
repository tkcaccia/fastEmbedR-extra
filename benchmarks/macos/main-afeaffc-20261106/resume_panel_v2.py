#!/usr/bin/env python3
"""Continue the stopped resident Mac panel without changing its source-locked cases."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


ROOT = Path('/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-afeaffc-benchmark-20261106')
PREVIOUS = Path('/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-afeaffc-resume-v1-20261106')
HERE = Path(__file__).resolve().parent
QUEUE_SHA256 = '6c5117feabdf20ebd02a1ebf6cc1de47430a8fa800e701f53ea03b7e7bc5a87d'
PREVIOUS_SHA256 = 'f3460d81c2c5c88e90e3566d32da07ecf73dee81c1747f555e734cf41782728f'
FILE_SHA256 = {
    'queue.py': '4712488628b550fada00af270cad0f34ef8bf4862ea99091bca79487498b1fdc',
    'run_case.py': '19add560dc73468551b803ffef08592f29dd75ef2bdbd4215333b25b4ca8a828',
    'policy.py': '13c7723adc4cca3334fa3b6669a22b92db9b97ef85dee8d2db6ebe296078345e',
    'worker.R': 'e772286c53536e009471f8b8a5ae2f09db67f01e161f8aee892a46d669619da4',
}
START_INDEX = 460  # Indices 458 and 459 timed out; preserve both results.
EXPECTED_TOTAL = 691
DISK_FLOOR_BYTES = 100 * 1024 ** 3
SWAP_GROWTH_LIMIT_MIB = 1024


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def record(**fields):
    with (HERE / 'resume-status.jsonl').open('a') as stream:
        stream.write(json.dumps({'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                                 **fields}, sort_keys=True) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def process_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def swap_mib():
    result = subprocess.run(['sysctl', 'vm.swapusage'], check=True,
                            text=True, capture_output=True, timeout=5)
    import re
    match = re.search(r'used = ([0-9.]+)([MG])', result.stdout)
    if not match:
        raise RuntimeError('Cannot measure swap')
    return float(match.group(1)) * (1024 if match.group(2) == 'G' else 1)


def deferred(case):
    # Both one- and four-core 965,282-row 3D t-SNE exceeded 1,800 seconds.
    # Preserve all analogous cases for separately budgeted longer runs.
    return (case['method'] == 't-SNE' and case['backend'] == 'cpu'
            and case['cores'] in (1, 4) and case['dimensions'] == 3
            and case['expected_rows'] >= 965282)


def preflight():
    if HERE == ROOT or not str(HERE).startswith('/Users/silvanopiazza/Documents/Stefano/'):
        raise RuntimeError('Versioned continuation must remain under Stefano')
    if digest(ROOT / 'queue.txt') != QUEUE_SHA256:
        raise RuntimeError('Original queue changed')
    for name, expected in FILE_SHA256.items():
        if digest(ROOT / name) != expected:
            raise RuntimeError('Original source changed: ' + name)
    queue = (ROOT / 'queue.txt').read_text().splitlines()
    if len(queue) != EXPECTED_TOTAL:
        raise RuntimeError('Original queue length changed')
    events = [json.loads(line) for line in (ROOT / 'queue-status.jsonl').read_text().splitlines()]
    if not events or events[-1].get('event') != 'stopped' or events[-1].get('index') != 458:
        raise RuntimeError('Original queue stop point differs')
    old_pid = int((ROOT / 'queue.lock').read_text().strip())
    if process_alive(old_pid):
        raise RuntimeError('Original queue PID is still live')
    failed_case = json.loads((ROOT / 'manifests' / queue[457]).read_text())
    failed_run = json.loads((Path(failed_case['output_dir']) / 'run.json').read_text())
    if failed_run.get('status') != 'failed' or not failed_run.get('timed_out'):
        raise RuntimeError('Original failed case differs')
    if digest(PREVIOUS / 'resume_panel_v1.py') != PREVIOUS_SHA256:
        raise RuntimeError('Previous continuation source changed')
    previous_events = [json.loads(line) for line in
                       (PREVIOUS / 'resume-status.jsonl').read_text().splitlines()]
    if not previous_events or previous_events[-1].get('event') != 'stopped' or \
            previous_events[-1].get('index') != 459 or \
            previous_events[-1].get('reason') != 'cleanup_or_timeout':
        raise RuntimeError('Previous continuation stop point differs')
    previous_pid = int((PREVIOUS / 'resume.lock').read_text().strip())
    if process_alive(previous_pid):
        raise RuntimeError('Previous continuation PID is still live')
    second_case = json.loads((ROOT / 'manifests' / queue[458]).read_text())
    second_run = json.loads((Path(second_case['output_dir']) / 'run.json').read_text())
    if second_run.get('status') != 'failed' or not second_run.get('timed_out'):
        raise RuntimeError('Second timed-out case differs')
    for name in queue[459:]:
        case = json.loads((ROOT / 'manifests' / name).read_text())
        if Path(case['output_dir']).exists():
            raise RuntimeError('Later output already exists: ' + case['case_id'])
    if shutil.disk_usage(ROOT).free < DISK_FLOOR_BYTES:
        raise RuntimeError('Disk floor reached')
    return queue


def main():
    if sys.platform != 'darwin':
        raise RuntimeError('Mac-only controller')
    HERE.mkdir(parents=True, exist_ok=True)
    with (HERE / 'resume.lock').open('x') as stream:
        stream.write(str(os.getpid()) + '\n')
    queue = preflight()
    initial_swap = swap_mib()
    record(event='started', pid=os.getpid(), queue_sha256=QUEUE_SHA256,
           controller_sha256=digest(Path(__file__)),
           previous_controller_sha256=PREVIOUS_SHA256,
           baseline_swap_mib=initial_swap,
           first_index=START_INDEX)
    consecutive_failures = 0
    deferred_count = 0
    for index in range(START_INDEX, len(queue) + 1):
        manifest = ROOT / 'manifests' / queue[index - 1]
        case = json.loads(manifest.read_text())
        if deferred(case):
            record(event='deferred', index=index, case_id=case['case_id'],
                   reason='965282_row_3d_cpu1_and_cpu4_tSNE_exceeded_1800_seconds')
            deferred_count += 1
            continue
        if Path(case['output_dir']).exists():
            raise RuntimeError('Output appeared during continuation')
        if shutil.disk_usage(ROOT).free < DISK_FLOOR_BYTES:
            record(event='stopped', index=index, reason='disk_floor')
            return 2
        current_swap = swap_mib()
        if current_swap - initial_swap > SWAP_GROWTH_LIMIT_MIB:
            record(event='stopped', index=index, reason='swap_growth', swap_mib=current_swap)
            return 2
        record(event='case_started', index=index, case_id=case['case_id'])
        with (HERE / 'worker-console.log').open('a') as log:
            code = subprocess.run(['/usr/bin/python3', str(ROOT / 'run_case.py'),
                                   str(manifest)], cwd=ROOT, check=False,
                                  stdout=log, stderr=subprocess.STDOUT).returncode
        run_path = Path(case['output_dir']) / 'run.json'
        run = json.loads(run_path.read_text()) if run_path.is_file() else {}
        record(event='case_finished', index=index, case_id=case['case_id'],
               exit_code=code, status=run.get('status'),
               cleanup_clear=run.get('cleanup_clear'), timed_out=run.get('timed_out'))
        if run.get('timed_out') or not run.get('cleanup_clear'):
            record(event='stopped', index=index, reason='cleanup_or_timeout')
            return 2
        consecutive_failures = consecutive_failures + 1 if code else 0
        if consecutive_failures >= 3:
            record(event='stopped', index=index, reason='three_consecutive_failures')
            return 2
    record(event='completed_with_deferred_cases' if deferred_count else 'completed',
           cases=len(queue), deferred=deferred_count)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        record(event='failed', error=repr(error))
        raise
