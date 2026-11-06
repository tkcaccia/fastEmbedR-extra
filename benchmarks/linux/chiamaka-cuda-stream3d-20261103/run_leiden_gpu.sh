#!/usr/bin/env bash
set -euo pipefail
root=/tmp/fastembedr_cuda_cluster_leiden_20261103
image=/mnt/sata_ssd/fastEmbedR/singularity/rebuild_20261029_a670bcc/fastembedr_a670bcc_20261029.sif
gpu=GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5
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
for attempt in 1 2 3; do
    idle_now || { echo "GPU occupied; no Leiden test launched."; exit 75; }
    sleep 15
done
idle_now || { echo "GPU admission changed; no test launched."; exit 75; }
status=0
timeout --signal=TERM --kill-after=10s 120s \
    singularity exec --cleanenv --nv --bind "$root:$root" \
    "$image" Rscript "$root/check_leiden_gpu.R" "$root" \
    > "$root/leiden_gpu.log" 2>&1 || status=$?
printf '%s\n' "$status" > "$root/leiden_gpu_exit"
contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
    --format=csv,noheader)
if [ -n "$contexts" ]; then
    echo "GPU context remained after Leiden probe: $contexts"
    exit 78
fi
cat "$root/leiden_gpu.log"
exit "$status"
