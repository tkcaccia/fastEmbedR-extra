#!/bin/bash
# Independent audit waits for the immutable Deep1B v3 queue to finish.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
campaign=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
run="${campaign}/deep1b-100m-v3"
post="${run}/postprocess"
queue="${run}/queue100m"
test ! -e "${post}/postprocess.exit"
trap 'code=$?; printf "%s\n" "${code}" > "${post}/postprocess.exit"' EXIT
for attempt in $(seq 1 64800); do
  [[ -e "${queue}/queue.exit" ]] && break
  sleep 60
done
[[ -e "${queue}/queue.exit" &&
  "$(cat "${queue}/queue.exit")" == 0 ]] || {
  echo "Deep1B queue did not finish successfully." >&2
  exit 1
}
[[ -z "$(pgrep -x 'R|Rscript' || true)" ]] || {
  echo "Another R worker is active after the 100M queue." >&2
  exit 1
}
export TMPDIR="${campaign}/tmp"
export XDG_CACHE_HOME="${campaign}/cache"
export R_LIBS_USER="${run}/Rlib:${campaign}/Rlib"
export OPENBLAS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1
export MKL_NUM_THREADS=1 OMP_NUM_THREADS=20
/usr/bin/python3 -u "${run}/benchmark/mac_long_guard_v1.py" \
  86400 "${post}/byte_guard.json" \
  /usr/bin/time -l -o "${post}/byte_time.txt" \
  /usr/bin/python3 -u "${post}/audit_deep1b_100m_mac_v1.py" \
  "${run}" > "${post}/byte_audit.log" 2>&1
/usr/bin/python3 -u "${run}/benchmark/mac_long_guard_v1.py" \
  86400 "${post}/graph_guard.json" \
  /usr/bin/time -l -o "${post}/graph_time.txt" \
  Rscript "${post}/audit_deep1b_100m_graphs_v1.R" \
  "${run}" > "${post}/graph_audit.log" 2>&1
