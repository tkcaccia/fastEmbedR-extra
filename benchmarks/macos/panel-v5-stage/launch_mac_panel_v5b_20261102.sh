#!/bin/bash
set -uo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
root=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
queue_id=panel_v5b_20261102
queue_root="${root}/results/m3-ultra-panel-v1-queue"
command -v R >/dev/null && command -v Rscript >/dev/null || exit 1
RUN=TRUE /bin/bash \
  "${root}/panel-v5/benchmark/benchmarks/macos/run_m3_ultra_panel_queue_v2.sh" \
  "${queue_id}"
result=$?
printf '%s\n' "${result}" > "${queue_root}/${queue_id}.launch.exit"
exit "${result}"
