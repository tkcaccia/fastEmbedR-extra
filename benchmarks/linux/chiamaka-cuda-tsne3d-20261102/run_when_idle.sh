#!/usr/bin/env bash
set -euo pipefail

root=/tmp/fastembedr_cuda_tsne3d_20261102
image=/mnt/sata_ssd/fastEmbedR/singularity/rebuild_20261029_a670bcc/fastembedr_a670bcc_20261029.sif
gpu=GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5
mkdir -p "$root/logs" "$root/results"
exec 9>"$root/queue.lock"
flock -n 9 || { echo "Another 3D test queue is active."; exit 70; }
trap 'echo "QUEUE_EXIT status=$? time=$(date -u +%FT%TZ)"' EXIT

printf '%s  %s\n' \
    3e81f859f48824825ed11928275954a062e6fd324e313bea515d43e1519db402 "$image" \
    5d0bee0b0951c07d0d3b504c17716016938d401dd23ce35739b8652a613c48c0 "$root/source.tar.gz" \
    c0d50292330cad4cd835394e5889b8b806e79d458d9b0beaecd2757421ef2839 "$root/library/fastEmbedR/libs/fastEmbedR.so" \
    a6cc5330aa00944f673a3180ae211a4958914172e19dfe09a57bab28d4ebf037 "$root/validate_3d.R" \
    7b78471a451f3d26daae48149c96bf7d5c1f35ebae84766c5cb15e2767662692 "$root/regress_2d.R" \
    1704c6d2137c6255e253a420ba4713de9e5a9d7d91974581ebe035a67f218382 "$root/validate_umap3d.R" \
    809250f5c13bf3d45b20718725a0e02483f28e4be972a8f9fc9ff35212bdaea3 "$root/regress_umap2d.R" | sha256sum -c -
observed=$(timeout 5s nvidia-smi --query-gpu=uuid --format=csv,noheader)
test "$observed" = "$gpu" || { echo "Assigned GPU changed."; exit 71; }
echo "QUEUE_START time=$(date -u +%FT%TZ) host=$(hostname) gpu=$gpu"

idle_now() {
    local contexts
    contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
        --format=csv,noheader) || return 1
    test -z "$contexts" || return 1
    ! pgrep -f '/home/chiamaka/Bora-benchmark-compute/' >/dev/null
}

deadline=$(($(date +%s) + 43200))
idle_since=0
admitted=0
while [ "$(date +%s)" -lt "$deadline" ]; do
    if idle_now; then
        if [ "$idle_since" -eq 0 ]; then
            idle_since=$(date +%s)
            echo "IDLE_OBSERVED time=$(date -u +%FT%TZ)"
        fi
        if [ "$(($(date +%s) - idle_since))" -ge 300 ]; then
            echo "IDLE_ADMITTED time=$(date -u +%FT%TZ)"
            admitted=1
            break
        fi
    elif [ "$idle_since" -ne 0 ]; then
        idle_since=0
        echo "IDLE_RESET time=$(date -u +%FT%TZ)"
    fi
    sleep 30
done
if [ "$admitted" -ne 1 ] || ! idle_now; then
    echo "QUEUE_EXPIRED without GPU work."
    exit 75
fi

verify_release() {
    local script=$1 contexts attempt
    for attempt in {1..10}; do
        contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
            --format=csv,noheader) || return 1
        if [ -z "$contexts" ] && ! pgrep -f "$root/$script" >/dev/null; then
            return 0
        fi
        sleep 1
    done
    echo "GPU context or owned process remains after $script: $contexts"
    return 1
}

case_pid=
active_script=
stop_queue() {
    trap - INT TERM HUP
    if [ -n "$case_pid" ]; then
        kill -TERM "$case_pid" 2>/dev/null || true
        for attempt in {1..10}; do
            kill -0 "$case_pid" 2>/dev/null || break
            sleep 1
        done
        kill -KILL "$case_pid" 2>/dev/null || true
        wait "$case_pid" 2>/dev/null || true
    fi
    if [ -n "$active_script" ]; then
        verify_release "$active_script" ||
            echo "CASE_UNSAFE_CLEANUP after queue interruption"
    fi
    echo "QUEUE_INTERRUPTED time=$(date -u +%FT%TZ)"
    exit 130
}
trap stop_queue INT TERM HUP

run_case() {
    local label=$1 script=$2 status=0
    shift 2
    if ! idle_now; then
        echo "ADMISSION_LOST $label time=$(date -u +%FT%TZ)"
        return 43
    fi
    echo "CASE_START $label time=$(date -u +%FT%TZ)"
    timeout --signal=TERM --kill-after=10s 120s \
        singularity exec --cleanenv --nv --bind "$root:$root" \
        "$image" /usr/bin/env \
        FASTEMBEDR_TEST_LIBRARY="$root/library" \
        FASTEMBEDR_CASE_SCRIPT="$root/$script" \
        /opt/r46/bin/Rscript -e \
        '.libPaths(c(Sys.getenv("FASTEMBEDR_TEST_LIBRARY"), \
          .libPaths())); source(Sys.getenv("FASTEMBEDR_CASE_SCRIPT"))' \
        "$@" \
        > "$root/logs/$label.log" 2>&1 &
    case_pid=$!
    active_script=$script
    wait "$case_pid" || status=$?
    case_pid=
    if ! verify_release "$script"; then
        echo "CASE_UNSAFE_CLEANUP $label"
        return 44
    fi
    if [ "$status" -ne 0 ]; then
        tail -n 50 "$root/logs/$label.log"
        echo "CASE_FAIL $label exit=$status"
        return "$status"
    fi
    tail -n 12 "$root/logs/$label.log"
    echo "CASE_PASS $label time=$(date -u +%FT%TZ)"
    active_script=
}

run_case tsne3d validate_3d.R
run_case umap3d validate_umap3d.R "$root/results/umap3d.csv"
run_case tsne2d regress_2d.R
run_case umap2d regress_umap2d.R "$root/results/umap2d.csv"
sha256sum "$root/logs"/{tsne3d,umap3d,tsne2d,umap2d}.log
echo "ALL_3D_DEVICE_TESTS_PASSED"
