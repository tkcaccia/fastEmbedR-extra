#!/bin/bash
set -uo pipefail
root=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
queue_id=panel_v5_20261102
queue_root="${root}/results/m3-ultra-panel-v1-queue"
RUN=TRUE /bin/bash \
  "${root}/panel-v5/benchmark/benchmarks/macos/run_m3_ultra_panel_queue_v2.sh" \
  "${queue_id}"
result=$?
printf '%s\n' "${result}" > "${queue_root}/${queue_id}.launch.exit"
exit "${result}"
