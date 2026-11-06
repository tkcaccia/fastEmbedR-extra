#!/usr/bin/env bash
set -euo pipefail
root=/tmp/fastembedr_pca_resident_20261103
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
    idle_now || { echo "GPU not idle; no PCA test launched."; exit 75; }
    sleep 15
done
idle_now || { echo "GPU admission changed; no PCA test launched."; exit 75; }
timeout --signal=TERM --kill-after=10s 120s \
    singularity exec --cleanenv --nv --bind "$root:$root" \
    "$image" Rscript "$root/check_single_gpu.R" "$root" \
    > "$root/single_gpu.log" 2>&1
status=$?
printf '%s\n' "$status" > "$root/single_gpu_exit"
contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
    --format=csv,noheader)
if [ -n "$contexts" ]; then
    echo "GPU context remained after PCA probe: $contexts"
    exit 78
fi
cat "$root/single_gpu.log"
exit "$status"
