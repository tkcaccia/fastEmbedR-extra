#!/usr/bin/env bash
set -u
root=/tmp/fastembedr_cuda_cluster_leiden_20261103
first=/tmp/fastembedr_cuda_cluster_20261103/queue_exit
exec 9>"$root/queue.lock"
flock -n 9 || { echo "Another Leiden probe is queued."; exit 70; }
for attempt in $(seq 1 70); do
    [ -f "$first" ] && break
    sleep 60
done
if [ ! -f "$first" ]; then
    printf '%s\n' 76 > "$root/queue_exit"
    echo "Previous CUDA probe remained queued; Leiden did not launch."
    exit 76
fi
for attempt in $(seq 1 60); do
    status=0
    bash "$root/run_leiden_gpu.sh" || status=$?
    if [ "$status" -ne 75 ]; then
        printf '%s\n' "$status" > "$root/queue_exit"
        exit "$status"
    fi
    sleep 60
done
printf '%s\n' 75 > "$root/queue_exit"
echo "GPU remained occupied; Leiden did not launch."
exit 75
