#!/usr/bin/env bash
set -euo pipefail

task_root=/tmp/fastembedr_cuda_candidate_20261104
image=/mnt/sata_ssd/fastEmbedR/singularity/rebuild_20261029_a670bcc/fastembedr_a670bcc_20261029.sif
expected_uuid=GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5
evidence="$task_root/gpu_probe_evidence_v2"
mkdir -p "$evidence"
date -u > "$evidence/admission.txt"
hostname >> "$evidence/admission.txt"
printf '%s\n' \
    "21f0ba4bb166b0a34a4658b24e840312d42ebb5178c07d21d83d010163b2d016  $task_root/chiamaka_gpu_cluster_probe_20261104.R" \
    "dbb0a7286537a0198c51ed9c04d5cdb3326c17217b1037e236635ebe1b406ddc  $task_root/fastembedr_gpu_probe_input_20261104.rds" \
    | sha256sum -c - > "$evidence/input_check.txt" || exit 26
sha256sum "$task_root/chiamaka_gpu_cluster_probe_20261104.R" \
    "$task_root/fastembedr_gpu_probe_input_20261104.rds" \
    "$image" > "$evidence/identities.sha256"
observed_uuid=$(timeout 5s nvidia-smi --query-gpu=uuid \
    --format=csv,noheader | head -n 1)
printf 'gpu_uuid=%s\n' "$observed_uuid" >> "$evidence/admission.txt"
if [[ "$observed_uuid" != "$expected_uuid" ]]; then
    echo 'GPU identity changed; no test launched.' >&2
    exit 20
fi
for sample in {1..13}; do
    printf 'idle_sample_%s=%s\n' "$sample" "$(date -u +%FT%TZ)" \
        >> "$evidence/admission.txt"
    if pgrep -f \
            'run_gpu_case.py|encode_spatial_full1280.py|bora-freeze-colorectal' \
            > "$evidence/bora_processes.txt"; then
        echo 'Bora GPU work is active; no test launched.' >&2
        exit 21
    fi
    contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
        --format=csv,noheader)
    if [[ -n "$contexts" ]]; then
        echo 'GPU compute context is occupied; no test launched.' >&2
        exit 22
    fi
    used=$(timeout 5s nvidia-smi --query-gpu=memory.used \
        --format=csv,noheader,nounits | head -n 1)
    printf 'idle_memory_mib_%s=%s\n' "$sample" "$used" \
        >> "$evidence/admission.txt"
    if (( used > 1024 )); then
        echo 'GPU memory exceeds idle allowance; no test launched.' >&2
        exit 23
    fi
    if (( sample < 13 )); then sleep 10; fi
done
date -u > "$evidence/started.txt"
set +e
timeout --signal=TERM --kill-after=30s 300s \
    singularity exec --nv "$image" /opt/r46/bin/Rscript \
    "$task_root/chiamaka_gpu_cluster_probe_20261104.R" \
    "$task_root/library" \
    "$task_root/fastembedr_gpu_probe_input_20261104.rds" \
    "$evidence/result.rds" > "$evidence/run.log" 2>&1 &
owner_pid=$!
printf '%s\n' "$owner_pid" > "$evidence/owner_pid.txt"
ps -o pid,ppid,pgid,lstart,command -p "$owner_pid" \
    > "$evidence/owner_process.txt"
wait "$owner_pid"
status=$?
set -e
printf '%s\n' "$status" > "$evidence/exit_status.txt"
date -u > "$evidence/finished.txt"
if pgrep -f 'chiamaka_gpu_cluster_probe_20261104.R' \
        > "$evidence/remaining_processes.txt"; then
    echo 'Owned R process remains after test; cleanup unknown.' >&2
    exit 25
fi
for attempt in 1 2 3; do
    if ! timeout 5s nvidia-smi --query-compute-apps=pid \
            --format=csv,noheader > "$evidence/contexts_$attempt.txt"; then
        echo 'GPU cleanup telemetry failed.' >&2
        exit 24
    fi
    if [[ -s "$evidence/contexts_$attempt.txt" ]]; then
        echo 'GPU context remains after test; cleanup unknown.' >&2
        exit 25
    fi
    sleep 2
done
if (( status != 0 )); then
    echo "GPU test failed with status $status; evidence retained." >&2
    exit "$status"
fi
cat "$evidence/run.log"
