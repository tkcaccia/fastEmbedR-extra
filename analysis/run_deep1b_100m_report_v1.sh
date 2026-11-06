#!/bin/bash
# Build the 100M supplement only from complete independent audit evidence.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
run="${campaign}/deep1b-100m-v3"
report="${run}/report-controller"
post="${run}/postprocess/postprocess.exit"
test ! -e "${report}/report.exit"
trap 'code=$?; printf "%s\n" "${code}" > "${report}/report.exit"' EXIT
for attempt in $(seq 1 64800); do
  [[ -e "${post}" ]] && break
  sleep 60
done
[[ -e "${post}" && "$(cat "${post}")" == 0 ]] || {
  echo "The independent 100M audit did not pass." >&2
  exit 1
}
/usr/bin/python3 -u "${report}/build_deep1b_100m_supplement_v1.py" \
  "${run}" > "${report}/report.log" 2>&1
shasum -a 256 "${run}/report/deep1b_100m_mac_stages.csv" \
  "${run}/report/deep1b_100m_mac_stages.tex" \
  > "${report}/report.sha256"
