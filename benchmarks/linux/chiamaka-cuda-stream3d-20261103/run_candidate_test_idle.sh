#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: bash run_candidate_test_idle.sh TEST_FILE DESCRIPTION" >&2
    exit 64
fi

test_file=$1
description=$2
root=/tmp/fastembedr_coord_full_20261103
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
    ! pgrep -f '/Bora-benchmark/' >/dev/null
}

for attempt in 1 2 3; do
    idle_now || { echo "GPU occupied; no test launched." >&2; exit 75; }
    sleep 10
done
idle_now || { echo "GPU admission changed; no test launched." >&2; exit 75; }

status=0
timeout --signal=TERM --kill-after=10s 180s \
    singularity exec --nv "$image" /opt/r46/bin/Rscript - \
    "$root/source/tests/testthat/$test_file" "$description" \
    "$root/library" <<'RS' || status=$?
args <- commandArgs(trailingOnly = TRUE)
.libPaths(c(args[[3L]], .libPaths()))
library(fastEmbedR)
testthat::test_file(args[[1L]], desc = args[[2L]],
    package = "fastEmbedR",
    reporter = testthat::StopReporter$new(praise = FALSE))
RS
contexts=$(timeout 5s nvidia-smi --query-compute-apps=pid \
    --format=csv,noheader) || exit 78
if [ -n "$contexts" ]; then
    echo "GPU context present after test; inspect before more work." >&2
    exit 78
fi
exit "$status"
