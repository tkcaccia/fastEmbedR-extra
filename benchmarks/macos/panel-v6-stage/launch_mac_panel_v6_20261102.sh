#!/usr/bin/env bash
# Autonomous Mac continuation; all output remains under Stefano.
set -uo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
queue_id=panel_v6_20261102
cd "${campaign}" || exit 1
status=0
RUN=TRUE /bin/bash \
  panel-v6/benchmark/benchmarks/macos/run_m3_ultra_panel_queue_v3.sh \
  "${queue_id}" || status=$?
printf '%s\n' "${status}" > \
  "${campaign}/results/m3-ultra-panel-v1-queue/${queue_id}.launch.exit"
exit "${status}"
