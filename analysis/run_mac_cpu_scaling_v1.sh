#!/bin/bash
# Run the CPU scaling report after the complete audited Mac panel.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
post="${campaign}/panel-v6/postprocess"
panel="${campaign}/results/m3-ultra-panel-v1-queue"
exit_file="${panel}/panel_v6_20261102.launch.exit"
test ! -e "${post}/cpu_scaling.exit"
trap 'code=$?; printf "%s\n" "${code}" > "${post}/cpu_scaling.exit"' EXIT
for attempt in $(seq 1 64800); do
  [[ -e "${exit_file}" ]] && break
  sleep 60
done
[[ -e "${exit_file}" && "$(cat "${exit_file}")" == 0 ]] || {
  echo "The full 11-dataset Mac panel did not pass." >&2
  exit 1
}
export FASTEMBEDR_MAC_SELECTOR="${campaign}/panel-v6/benchmark/benchmarks/macos/derive_m3_ultra_selector_v2.py"
/usr/bin/python3 -u "${post}/build_mac_cpu_scaling_v1.py" \
  "${panel}/panel_v6_20261102" "${campaign}" \
  "${post}/mac_cpu_scaling_v1" > "${post}/cpu_scaling.log" 2>&1
shasum -a 256 "${post}/mac_cpu_scaling_v1.csv" \
  "${post}/mac_cpu_scaling_v1_summary.csv" \
  "${post}/mac_cpu_scaling_v1.tex" \
  > "${post}/cpu_scaling.sha256"
