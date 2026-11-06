#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"
root=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
queue_id="${1:-}"
[[ "${queue_id}" =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
status="${root}/results/deep1b-full-download-20261101/status.json"
qual="${root}/results/m3-ultra-candidate-qualification/qual_clt_v8_20261101"
archive="${root}/candidates/mac-benchmark-integration-20261102-v3/fastEmbedR_0.1.tar.gz"
expected=ae37cd4f3638ec59d515456e5c6e0c1bf6d38de8fba05414aab471a0abd76e00
for check in $(seq 1 288); do
  state="$(python3 - "${status}" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
print(json.loads(path.read_text()).get("status", "unknown")
      if path.is_file() else "missing")
PY
)"
  case "${state}" in
    complete) break ;;
    failed|stopping_low_space)
      echo "Deep1B download failed: ${state}" >&2; exit 1 ;;
    running|starting|missing) ;;
    *) echo "Unexpected download state: ${state}" >&2; exit 1 ;;
  esac
  sleep 300
done
[[ "${state}" == complete ]] || {
  echo "Deep1B download wait exceeded 24 hours." >&2; exit 1;
}
python3 - "${root}" <<'PY'
import json
import struct
import sys
from pathlib import Path
root = Path(sys.argv[1])
data = root / "data/BigANN/deep/1000000000/base.1000000000.fbin"
manifest = json.loads((data.parent / "manifest.json").read_text())
if (data.stat().st_size != 384000000008 or
        manifest.get("rows") != 1000000000 or
        manifest.get("columns") != 96 or
        manifest.get("bytes") != data.stat().st_size or
        len(manifest.get("sha256", "")) != 64):
    raise SystemExit("Deep1B final input identity is incomplete")
with data.open("rb") as stream:
    if struct.unpack("<II", stream.read(8)) != (1000000000, 96):
        raise SystemExit("Deep1B header changed")
PY
[[ "$(cat "${qual}.launch.exit")" == 0 ]] || {
  echo "Mac package qualification did not pass." >&2; exit 1;
}
grep -q '^identity,pass$' "${qual}/completed.csv"
[[ "$(shasum -a 256 "${archive}" | cut -d' ' -f1)" == \
   "${expected}" ]] || {
  echo "Qualified archive hash changed." >&2; exit 1;
}
if pgrep -x R >/dev/null || pgrep -x Rscript >/dev/null; then
  echo "Another R process is active; refusing benchmark timing." >&2
  exit 1
fi
free_kib="$(df -Pk "${root}" | awk 'NR == 2 {print $4}')"
(( free_kib >= 80 * 1024 * 1024 )) || {
  echo "Mac has less than 80 GiB free." >&2; exit 1;
}
RUN=TRUE /bin/bash "${script_dir}/run_m3_ultra_panel_queue_v2.sh" \
  "${queue_id}"
