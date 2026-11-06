#!/usr/bin/env bash
set -euo pipefail

root=/tmp/fastembedr_resident_umap_20261103
image=/mnt/sata_ssd/fastEmbedR/singularity/rebuild_20261029_a670bcc/fastembedr_a670bcc_20261029.sif
gpu=GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5
exec 9>"$root/queue_umap.lock"
flock -n 9 || { echo "Another UMAP probe is active."; exit 70; }
trap 'status=$?; printf "%s\n" "$status" > "$root/queue_umap_exit"' EXIT

printf '%s  %s\n' \
    3e81f859f48824825ed11928275954a062e6fd324e313bea515d43e1519db402 "$image" \
    a18c7f2e83b380fc0bde5d508fe3d6aab7dd9e473562bdc11b811d8e952a1079 "$root/library/fastEmbedR/libs/fastEmbedR.so" \
    1665bdbe91d3c87f5d5934cb3301299e1d3c63cf2b7db1e1ea51033f284153b3 "$root/check_umap_single_gpu.R" | sha256sum -c -

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
    idle_now || { echo "GPU not idle; no test launched."; exit 75; }
    sleep 15
done
idle_now || { echo "GPU admission changed; no test launched."; exit 75; }
echo "UMAP_CASE_START $(date -u +%FT%TZ)"
status=0
timeout --signal=TERM --kill-after=10s 120s \
    singularity exec --cleanenv --nv --bind "$root:$root" \
    "$image" Rscript "$root/check_umap_single_gpu.R" "$root" \
    > "$root/umap_single_gpu.log" 2>&1 || status=$?
contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
    --format=csv,noheader)
if [ -n "$contexts" ]; then
    echo "GPU context remained after UMAP probe: $contexts"
    exit 78
fi
cat "$root/umap_single_gpu.log"
echo "UMAP_CASE_EXIT $status $(date -u +%FT%TZ)"
exit "$status"
