#!/bin/bash
# Audit the 11-dataset panel only after its independent stages complete.
set -euo pipefail

campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
controller="${campaign}/panel-only-audit-controller-v1"
script="${campaign}/analysis/audit_mac_panel_only_v1.py"
helper="${campaign}/final-audit-controller/audit_mac_campaign_complete_v1.py"
expected=56ce08bd060f83b2d294b07a6c8b0a9ff3b89633bac64408c5696a7d948e7345
[[ -f "$script" && -f "$helper" && ! -e "$controller" ]] || exit 70
[[ "$(shasum -a 256 "$script" | awk '{print $1}')" == "$expected" ]] || exit 71
mkdir "$controller"
trap 'code=$?; printf "%s\n" "$code" > "$controller/audit.exit"' EXIT
cp "$script" "$controller/audit_script.lock.py"
shasum -a 256 "$helper" > "$controller/helper.lock.sha256"
echo "AUDIT_WAIT_START $(date -u +%FT%TZ)"

exits=(
  results/m3-ultra-panel-v1-queue/panel_v6_20261102.launch.exit
  panel-v6/postprocess/supplement.exit
  panel-v6/postprocess/cpu_scaling.exit
)
ready=false
for attempt in $(seq 1 10080); do
  ready=true
  for name in "${exits[@]}"; do
    path="$campaign/$name"
    if [[ ! -f "$path" ]]; then
      ready=false
    elif [[ "$(cat "$path")" != 0 ]]; then
      echo "AUDIT_PREREQUISITE_FAILED $name" >&2
      exit 1
    fi
  done
  [[ "$ready" == true ]] && break
  sleep 60
done
[[ "$ready" == true ]] || {
  echo "AUDIT_WAIT_EXPIRED" >&2
  exit 75
}
[[ "$(shasum -a 256 "$script" | awk '{print $1}')" == "$expected" ]] || exit 71
shasum -a 256 -c "$controller/helper.lock.sha256"
echo "AUDIT_PREREQUISITES_PASSED $(date -u +%FT%TZ)"
/usr/bin/python3 -u "$controller/audit_script.lock.py" "$campaign" \
  > "$controller/audit.log" 2>&1
shasum -a 256 "$campaign/panel-only-audit-v1/audit.json" \
  > "$controller/audit.sha256"
echo "PANEL_ONLY_AUDIT_COMPLETE $(date -u +%FT%TZ)"
