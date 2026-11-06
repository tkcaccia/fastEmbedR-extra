#!/bin/bash
# Descriptive 100M layout check after independent structural audits.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
run="${campaign}/deep1b-100m-v3"
controller="${run}/layout-quality-controller"
post="${run}/postprocess/postprocess.exit"
test ! -e "${controller}/layout_quality.exit"
trap 'code=$?; printf "%s\n" "${code}" > "${controller}/layout_quality.exit"' EXIT
for attempt in $(seq 1 64800); do
  [[ -e "${post}" ]] && break
  sleep 60
done
[[ -e "${post}" && "$(cat "${post}")" == 0 ]] || {
  echo "The independent 100M structural audit did not pass." >&2
  exit 1
}
export TMPDIR="${campaign}/tmp"
/usr/bin/python3 -u "${run}/benchmark/mac_long_guard_v1.py" \
  86400 "${controller}/guard.json" \
  /usr/bin/time -l -o "${controller}/time.txt" \
  /usr/bin/python3 -u \
  "${controller}/audit_deep1b_100m_layout_quality_v1.py" \
  "${run}" > "${controller}/layout_quality.log" 2>&1
shasum -a 256 "${run}/layout-quality-v1/neighbor_vs_random.csv" \
  "${run}/layout-quality-v1/method.json" \
  > "${controller}/layout_quality.sha256"
