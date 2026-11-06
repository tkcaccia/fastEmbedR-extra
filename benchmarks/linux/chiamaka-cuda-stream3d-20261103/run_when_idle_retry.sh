#!/usr/bin/env bash
set -euo pipefail

root=/tmp/fastembedr_cuda_stream3d_20261103
image=/mnt/sata_ssd/fastEmbedR/singularity/rebuild_20261029_a670bcc/fastembedr_a670bcc_20261029.sif
gpu=GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5
exec 9>"$root/queue_retry.lock"
flock -n 9 || { echo "Another 3D CUDA queue is active."; exit 70; }
trap 'status=$?; printf "%s\n" "$status" > "$root/queue_retry_exit"' EXIT

printf '%s  %s\n' \
    3e81f859f48824825ed11928275954a062e6fd324e313bea515d43e1519db402 "$image" \
    69bd70a2884c628ca5baaaac2a8dc8d4a6da19c137f106bc49a08dfcd2577e49 "$root/library/fastEmbedR/libs/fastEmbedR.so" \
    669663e6d75eb74ea3be97cfbc5f09e74ce759f2c6ec1175ab6156506d61c624 "$root/source/src/massive_matrix.cpp" \
    57ae6ae2ef40cf90381980d80211fdc0047f68d536f9e279d160a3d6ef7f2c17 "$root/source/src/embedding_cuda_kernels.cpp" \
    e8f56f1252270ab7d2f4b0ee9a224cd9ef534823a0cdc670e1465696acc04f33 "$root/source/src/massive_tsne_cuda.h" \
    eb462ed2d9a94fe06ae1ad4851b301384f3672261140cf013aceb23676273155 "$root/check_cuda_checkpoint_3d.R" \
    1c5bdc74efef83cb727cda9be8089d365cf2fa1e422435799194228a197f6155 "$root/check_cuda_checkpoint_2d.R" | sha256sum -c -

idle_now() {
    local observed contexts
    observed=$(timeout 5s nvidia-smi --query-gpu=uuid \
        --format=csv,noheader) || return 1
    [ "$observed" = "$gpu" ] || return 1
    contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
        --format=csv,noheader) || return 1
    [ -z "$contexts" ] || return 1
    ! pgrep -f '/home/chiamaka/Bora-benchmark-compute/' >/dev/null
}

case_pid=
stop_queue() {
    trap - INT TERM HUP
    if [ -n "$case_pid" ]; then
        kill -TERM -- "-$case_pid" 2>/dev/null || true
        wait "$case_pid" 2>/dev/null || true
    fi
    echo "QUEUE_INTERRUPTED $(date -u +%FT%TZ)"
    exit 130
}
trap stop_queue INT TERM HUP

deadline=$(($(date +%s) + 43200))
idle_since=0
while [ "$(date +%s)" -lt "$deadline" ]; do
    if idle_now; then
        if [ "$idle_since" -eq 0 ]; then
            idle_since=$(date +%s)
            echo "IDLE_OBSERVED $(date -u +%FT%TZ)"
        fi
        if [ "$(($(date +%s) - idle_since))" -ge 30 ]; then
            echo "IDLE_ADMITTED $(date -u +%FT%TZ)"
            break
        fi
    else
        idle_since=0
    fi
    sleep 15
done
if ! idle_now || [ "$idle_since" -eq 0 ] ||
    [ "$(($(date +%s) - idle_since))" -lt 30 ]; then
    echo "QUEUE_EXPIRED without GPU work."
    exit 75
fi

run_case() {
    local name=$1 script=$2 status=0 contexts
    idle_now || { echo "ADMISSION_LOST $name"; return 76; }
    echo "CASE_START $name $(date -u +%FT%TZ)"
    setsid timeout --signal=TERM --kill-after=10s 120s \
        singularity exec --cleanenv --nv --bind "$root:$root" \
        "$image" env R_LIBS="$root/library" Rscript \
        "$root/$script" "$root" > "$root/retry_$name.log" 2>&1 &
    case_pid=$!
    wait "$case_pid" || status=$?
    case_pid=
    contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
        --format=csv,noheader) || return 77
    if [ -n "$contexts" ]; then
        echo "CASE_UNSAFE_CLEANUP $name pid=$contexts"
        return 78
    fi
    echo "CASE_EXIT $name status=$status $(date -u +%FT%TZ)"
    return "$status"
}

run_case cuda_checkpoint_3d check_cuda_checkpoint_3d.R
run_case cuda_checkpoint_2d check_cuda_checkpoint_2d.R
echo "ALL_3D_AND_2D_TESTS_PASSED"
