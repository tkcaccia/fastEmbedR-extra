#!/usr/bin/env python3
"""One resident-memory Slurm GPU case with bounded owned-workload cleanup."""
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path('/scratch/firenze/NN/benchmarks/resident_gpu_matched_afeaffc_v2')
IMAGE = Path('/scratch/firenze/NN/singularity/release_afeaffc_20261106/fastembedr_afeaffc_20261106.sif')
WORKER = ROOT / 'run_case_gpu.py'
ABORT = None


def log(event, **fields):
    print(json.dumps(dict(event=event, utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',
          time.gmtime()), **fields), sort_keys=True), flush=True)


def on_signal(number, _frame):
    global ABORT
    ABORT = signal.Signals(number).name


def checked_command(args, seconds=5):
    return subprocess.run(args, check=True, capture_output=True, text=True,
                          timeout=seconds).stdout


def gpu_inventory():
    rows = checked_command(['nvidia-smi', '--query-gpu=index,uuid',
                            '--format=csv,noheader,nounits'])
    return dict(line.strip().split(', ', 1) for line in rows.splitlines()
                if line.strip())


def resolve_allocated_uuids(allocated, visible, inventory, count):
    slurm_ids = allocated.split(',')
    cuda_ids = visible.split(',')
    if (count not in (1, 2, 3) or
            len(slurm_ids) != count or len(set(slurm_ids)) != count or
            len(cuda_ids) != count or len(set(cuda_ids)) != count or
            set(cuda_ids) != set(inventory)):
        raise RuntimeError('Cannot prove the visible GPUs are allocated')
    if len(inventory) != len(slurm_ids):
        raise RuntimeError('GPU inventory includes unassigned devices')
    uuids = set(inventory.values())
    if len(uuids) != count or not all(
            item.startswith('GPU-') for item in uuids):
        raise RuntimeError('Assigned GPU UUIDs are missing or duplicate')
    return uuids


def assigned_uuids(count):
    job = os.environ.get('SLURM_JOB_ID')
    allocated = os.environ.get('SLURM_JOB_GPUS')
    visible = os.environ.get('CUDA_VISIBLE_DEVICES')
    if not job or not allocated or not visible:
        raise RuntimeError('Missing Slurm GPU allocation identity')
    inventory = gpu_inventory()
    uuids = resolve_allocated_uuids(allocated, visible, inventory, count)
    log('allocation', job=job, host=os.uname().nodename,
        slurm_job_gpus=allocated, cuda_visible_devices=visible,
        visible_inventory=inventory, assigned_uuids=sorted(uuids))
    return uuids


def contexts(uuids):
    rows = checked_command(['nvidia-smi',
        '--query-compute-apps=pid,gpu_uuid',
        '--format=csv,noheader,nounits'])
    found = set()
    for line in rows.splitlines():
        if not line.strip():
            continue
        parts = [part.strip() for part in line.split(',')]
        if len(parts) != 2 or not parts[0].isdigit():
            raise RuntimeError('Ambiguous GPU context telemetry: ' + line)
        if parts[1] in uuids:
            found.add((int(parts[0]), parts[1]))
    return found


def gpu_memory_mib(uuids):
    rows = checked_command(['nvidia-smi',
        '--query-gpu=uuid,memory.used',
        '--format=csv,noheader,nounits'])
    memory = {}
    for row in rows.splitlines():
        parts = [part.strip() for part in row.split(',')]
        if len(parts) != 2 or not parts[1].isdigit():
            raise RuntimeError('Ambiguous GPU memory telemetry: ' + row)
        if parts[0] in uuids:
            memory[parts[0]] = int(parts[1])
    if set(memory) != uuids:
        raise RuntimeError('Assigned GPU memory telemetry is incomplete')
    return memory


def group_pids(pgid):
    found = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            stat = (proc / 'stat').read_text().rsplit(')', 1)[1].split()
            if stat[0] != 'Z' and int(stat[2]) == pgid:
                found.add(int(proc.name))
        except (OSError, IndexError, ValueError):
            continue
    return found


def stop_group(pgid):
    for sig, seconds in ((signal.SIGTERM, 10), (signal.SIGKILL, 10)):
        members = group_pids(pgid)
        if not members:
            return
        log('shutdown', signal=sig.name, pids=sorted(members))
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            pass
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if not group_pids(pgid):
                return
            time.sleep(0.5)


def verify_cleanup(pgid, uuids):
    for attempt in range(15):
        members = group_pids(pgid)
        active = contexts(uuids)
        if not members and not active:
            log('cleanup_verified', attempts=attempt + 1)
            return
        time.sleep(1)
    raise RuntimeError('Cleanup unknown: owned process group or assigned '
                       'GPU context remains')


def main():
    signal.signal(signal.SIGUSR1, on_signal)
    signal.signal(signal.SIGTERM, on_signal)
    case = json.loads((ROOT / 'case.json').read_text())
    count = case.get('gpus')
    if type(count) is not int or count not in (1, 2, 3):
        raise RuntimeError('CUDA case requests an unsupported GPU count')
    identity = Path('/scratch/firenze/NN/singularity/release_afeaffc_20261106/release_inputs/source-identity.txt').read_text()
    if 'FastEmbedRCommit=afeaffc39a607c00db5899c284451c6cdbf741bb' not in identity.splitlines():
        raise RuntimeError('Package source identity mismatch')
    if IMAGE.stat().st_mode & 0o222:
        raise RuntimeError('Image must remain read-only')
    expected = Path('/scratch/firenze/NN/singularity/release_afeaffc_20261106/image-final.sha256').read_text().split()[0]
    log('image_approved', sha256=expected, image=str(IMAGE))
    uuids = assigned_uuids(count)
    if contexts(uuids):
        raise RuntimeError('Assigned GPU already has compute contexts')
    baseline_mib = gpu_memory_mib(uuids)
    peak_mib = dict(baseline_mib)
    if ABORT:
        raise RuntimeError('Scheduler warning before launch: ' + ABORT)
    command = ['singularity', 'exec', '--nv',
               '--bind', '/scratch/firenze/NN:/scratch/firenze/NN',
               str(IMAGE), '/opt/conda/bin/python', str(WORKER),
               str(ROOT / 'case.json'), '/scratch/firenze/NN/Data',
               str(ROOT / 'results')]
    proc = subprocess.Popen(command, start_new_session=True)
    pgid = proc.pid
    log('child_started', pid=proc.pid, pgid=pgid, command=command)
    failed = None
    deadline = time.monotonic() + 180
    next_sample = 0
    try:
        while proc.poll() is None:
            now = time.monotonic()
            if ABORT:
                failed = 'Scheduler warning: ' + ABORT
                break
            if now >= deadline:
                failed = 'Application deadline exceeded'
                break
            if now >= next_sample:
                active = contexts(uuids)
                current_mib = gpu_memory_mib(uuids)
                for uuid in uuids:
                    peak_mib[uuid] = max(peak_mib[uuid],
                                         current_mib[uuid])
                log('gpu_telemetry',
                    pids=sorted({pid for pid, _ in active}),
                    memory_mib=current_mib)
                next_sample = now + 1
            time.sleep(0.5)
        if proc.poll() is not None and proc.returncode != 0:
            failed = 'Worker exit: ' + str(proc.returncode)
    except Exception as exc:
        failed = 'Monitoring failed: ' + repr(exc)
    finally:
        stop_group(pgid)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            failed = 'Child reap timeout'
        verify_cleanup(pgid, uuids)
    if failed:
        raise RuntimeError(failed)
    result = ROOT / 'results' / case['case_id']
    provenance = json.loads((result / 'provenance.json').read_text())
    metrics = json.loads((result / 'metrics.json').read_text())
    quality = metrics.get('quality')
    quality_ok = isinstance(quality, dict) and all(
        type(quality.get(key)) in (int, float) and
        math.isfinite(quality[key]) and 0 <= quality[key] <= 1
        for key in ('trustworthiness', 'label_accuracy'))
    if (provenance.get('status') != 'completed' or
            metrics.get('case_id') != case['case_id'] or
            metrics.get('observed_backend') != 'cuda' or
            metrics.get('gpu_devices') != list(range(count)) or
            metrics.get('n_rows') != case['expected_rows'] or
            metrics.get('n_columns') != case['expected_columns'] or
            metrics.get('preprocessing_rank') != 30 or
            not quality_ok or
            not (result / 'output.rds').is_file()):
        raise RuntimeError('CUDA fit output or backend evidence invalid')
    telemetry = {'baseline_mib': baseline_mib,
                 'peak_mib': peak_mib,
                 'peak_above_baseline_mib': {
                     uuid: peak_mib[uuid] - baseline_mib[uuid]
                     for uuid in uuids}}
    if any(value <= 0 for value in
           telemetry['peak_above_baseline_mib'].values()):
        raise RuntimeError('Every assigned GPU must use device memory')
    (result / 'gpu_memory.json').write_text(
        json.dumps(telemetry, sort_keys=True, indent=2) + '\n')
    log('pilot_pass', exit_code=proc.returncode,
        case_id=metrics['case_id'], devices=metrics['gpu_devices'],
        gpu_peak_mib=peak_mib)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        log('pilot_fail', reason=repr(exc))
        sys.exit(1)
