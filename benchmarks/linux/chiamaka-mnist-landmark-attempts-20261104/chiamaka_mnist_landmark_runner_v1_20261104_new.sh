#!/usr/bin/env bash
set -euo pipefail

task_root=/tmp/fastembedr_cuda_candidate_20261104
image=/mnt/sata_ssd/fastEmbedR/singularity/rebuild_20261029_a670bcc/fastembedr_a670bcc_20261029.sif
dataset=/mnt/sata_ssd/fastEmbedR_Data/MNIST/MNIST_float32.RData
expected_uuid=GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5
evidence="$task_root/mnist_landmark3d_evidence_v1"
if [[ -e "$evidence/admission.txt" ]]; then
    echo 'This evidence path was already attempted.' >&2
    exit 27
fi
mkdir -p "$evidence"
date -u > "$evidence/admission.txt"
hostname >> "$evidence/admission.txt"
printf '%s\n' \
    "4507d67a6c1a8bcb211f8bd358374ec423a6b90982cde4308ef2a08b17fcdc24  $task_root/chiamaka-mnist-landmark-3d-20261104.R" \
    "8b2e81ad007834885b192f1eae90261fa93dad2e85f1e185518f74c659772151  $task_root/common.R" \
    "0e1fefab430cded89c2c36871540aea87deee1a1316e1a7d6ea4d31c07f835b0  $dataset" \
    "8a5d24639cb7a000cfc9bc1b653b6c3567e835fdf5bc0fcbed248483c19fea17  $task_root/library/fastEmbedR/libs/fastEmbedR.so" \
    | sha256sum -c - > "$evidence/input_check.txt" || exit 26
sha256sum "$image" > "$evidence/image.sha256"
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
timeout --signal=TERM --kill-after=30s 180s \
    singularity exec --nv "$image" /opt/r46/bin/Rscript \
    "$task_root/chiamaka-mnist-landmark-3d-20261104.R" \
    "$task_root/library" "$evidence/result.rds" \
    "$task_root/common.R" > "$evidence/run.log" 2>&1 &
owner_pid=$!
printf '%s\n' "$owner_pid" > "$evidence/owner_pid.txt"
ps -o pid,ppid,pgid,lstart,command -p "$owner_pid" \
    > "$evidence/owner_process.txt"
(
    while kill -0 "$owner_pid" 2>/dev/null; do
        if pgrep -f \
                'run_gpu_case.py|encode_spatial_full1280.py|bora-freeze-colorectal' \
                > "$evidence/bora_during_run.txt"; then
            echo 'Bora appeared; stopping only this quality test.' \
                > "$evidence/monitor.txt"
            kill -TERM "$owner_pid" 2>/dev/null || true
            break
        fi
        sleep 2
    done
) &
monitor_pid=$!
wait "$owner_pid"
status=$?
kill "$monitor_pid" 2>/dev/null || true
wait "$monitor_pid" 2>/dev/null || true
set -e
printf '%s\n' "$status" > "$evidence/exit_status.txt"
date -u > "$evidence/finished.txt"
if pgrep -f 'chiamaka-mnist-landmark-3d-20261104.R' \
        > "$evidence/remaining_processes.txt"; then
    echo 'Owned R process remains; cleanup unknown.' >&2
    exit 25
fi
for attempt in 1 2 3; do
    if ! timeout 5s nvidia-smi --query-compute-apps=pid \
            --format=csv,noheader > "$evidence/contexts_$attempt.txt"; then
        echo 'GPU cleanup telemetry failed.' >&2
        exit 24
    fi
    if [[ -s "$evidence/contexts_$attempt.txt" ]]; then
        echo 'GPU context remains; cleanup unknown.' >&2
        exit 25
    fi
    sleep 2
done
if (( status != 0 )); then
    tail -n 80 "$evidence/run.log" >&2
    echo "GPU quality test failed with status $status." >&2
    exit "$status"
fi
cat "$evidence/run.log"
