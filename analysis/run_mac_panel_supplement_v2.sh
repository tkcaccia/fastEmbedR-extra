#!/bin/bash
# Emit the Mac supplement after all 11 dataset audits finish.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
post="${campaign}/panel-v6/postprocess"
queue="${campaign}/results/m3-ultra-panel-v1-queue"
panel="${queue}/panel_v6_20261102"
exit_file="${queue}/panel_v6_20261102.launch.exit"
test ! -e "${post}/supplement.exit"
trap 'code=$?; printf "%s\n" "${code}" > "${post}/supplement.exit"' EXIT
for attempt in $(seq 1 64800); do
  [[ -e "${exit_file}" ]] && break
  sleep 60
done
[[ -e "${exit_file}" && "$(cat "${exit_file}")" == 0 ]] || {
  echo "The complete Mac panel did not pass its audit." >&2
  exit 1
}
export FASTEMBEDR_MAC_SELECTOR="${campaign}/panel-v6/benchmark/benchmarks/macos/derive_m3_ultra_selector_v2.py"
/usr/bin/python3 -u "${post}/build_mac_panel_supplement_v2.py" \
  "${panel}" "${campaign}" "${post}/mac_panel_11datasets_v2" \
  > "${post}/supplement.log" 2>&1
shasum -a 256 "${post}/mac_panel_11datasets_v2.csv" \
  "${post}/mac_panel_11datasets_v2.tex" \
  > "${post}/supplement.sha256"
