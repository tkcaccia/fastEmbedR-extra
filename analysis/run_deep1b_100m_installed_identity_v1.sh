#!/bin/bash
# Verify the installed binary after the 100M run and structural audit.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
run="${campaign}/deep1b-100m-v3"
controller="${run}/installed-identity-controller"
post="${run}/postprocess/postprocess.exit"
test ! -e "${controller}/identity.exit"
trap 'code=$?; printf "%s\n" "${code}" > "${controller}/identity.exit"' EXIT
for attempt in $(seq 1 64800); do
  [[ -e "${post}" ]] && break
  sleep 60
done
[[ -e "${post}" && "$(cat "${post}")" == 0 ]] || {
  echo "The independent 100M structural audit did not pass." >&2
  exit 1
}
/usr/bin/python3 -u \
  "${controller}/audit_deep1b_100m_installed_identity_v1.py" \
  "${run}" > "${controller}/identity.log" 2>&1
shasum -a 256 "${run}/installed-identity-audit-v1/identity.json" \
  > "${controller}/identity.sha256"
