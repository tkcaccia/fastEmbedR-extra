#!/usr/bin/env python3
"""One resident-memory Slurm GPU case with bounded owned-workload cleanup."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path('/scratch/firenze/NN/singularity/candidate_b825116_20261104')
IMAGE = ROOT / 'fastembedr_b825116_20261104.sif'
WORKER = ROOT / 'hpc_resident_pilot_b825116.R'
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


def resolve_allocated_uuids(allocated, visible, inventory):
    slurm_ids = allocated.split(',')
    cuda_ids = visible.split(',')
    if (len(slurm_ids) != 2 or len(set(slurm_ids)) != 2 or
            len(cuda_ids) != 2 or len(set(cuda_ids)) != 2 or
            set(cuda_ids) != set(inventory)):
        raise RuntimeError('Cannot prove the two visible GPUs are allocated')
    if len(inventory) != len(slurm_ids):
        raise RuntimeError('GPU inventory includes unassigned devices')
    uuids = set(inventory.values())
    if len(uuids) != 2 or not all(item.startswith('GPU-') for item in uuids):
        raise RuntimeError('Assigned GPU UUIDs are missing or duplicate')
    return uuids


def assigned_uuids():
    job = os.environ.get('SLURM_JOB_ID')
    allocated = os.environ.get('SLURM_JOB_GPUS')
    visible = os.environ.get('CUDA_VISIBLE_DEVICES')
    if not job or not allocated or not visible:
        raise RuntimeError('Missing Slurm GPU allocation identity')
    inventory = gpu_inventory()
    uuids = resolve_allocated_uuids(allocated, visible, inventory)
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
    expected = (ROOT / 'image-1570377.sha256').read_text().split()[0]
    digest = hashlib.sha256()
    with IMAGE.open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(block)
    actual = digest.hexdigest()
    if actual != expected:
        raise RuntimeError('Immutable image checksum mismatch')
    log('image_verified', sha256=actual, image=str(IMAGE))
    uuids = assigned_uuids()
    if contexts(uuids):
        raise RuntimeError('Assigned GPU already has compute contexts')
    if ABORT:
        raise RuntimeError('Scheduler warning before launch: ' + ABORT)
    command = ['singularity', 'exec', '--nv', str(IMAGE),
               '/opt/r46/bin/Rscript', str(WORKER)]
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
                log('gpu_contexts', pids=sorted({pid for pid, _ in active}))
                next_sample = now + 5
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
    log('pilot_pass', exit_code=proc.returncode)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        log('pilot_fail', reason=repr(exc))
        sys.exit(1)
