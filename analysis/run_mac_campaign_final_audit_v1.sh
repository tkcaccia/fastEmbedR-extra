#!/bin/bash
# Cross-check all audited Mac results before manuscript integration.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
controller="${campaign}/final-audit-controller"
test ! -e "${controller}/final_audit.exit"
trap 'code=$?; printf "%s\n" "${code}" > "${controller}/final_audit.exit"' EXIT
exits=(
  results/m3-ultra-panel-v1-queue/panel_v6_20261102.launch.exit
  panel-v6/postprocess/supplement.exit
  panel-v6/postprocess/cpu_scaling.exit
  deep1b-100m-v3/queue100m/queue.exit
  deep1b-100m-v3/postprocess/postprocess.exit
  deep1b-100m-v3/report-controller/report.exit
  deep1b-100m-v3/layout-quality-controller/layout_quality.exit
  deep1b-100m-v3/installed-identity-controller/identity.exit
)
for attempt in $(seq 1 64800); do
  ready=true
  for name in "${exits[@]}"; do
    path="${campaign}/${name}"
    if [[ ! -e "${path}" ]]; then
      ready=false
    elif [[ "$(cat "${path}")" != 0 ]]; then
      echo "Required Mac campaign stage failed: ${name}" >&2
      exit 1
    fi
  done
  [[ "${ready}" == true ]] && break
  sleep 60
done
[[ "${ready}" == true ]] || {
  echo "Mac campaign did not finish within 45 days." >&2
  exit 1
}
/usr/bin/python3 -u \
  "${controller}/audit_mac_campaign_complete_v1.py" \
  "${campaign}" > "${controller}/final_audit.log" 2>&1
shasum -a 256 "${campaign}/final-campaign-audit-v1/audit.json" \
  > "${controller}/final_audit.sha256"
