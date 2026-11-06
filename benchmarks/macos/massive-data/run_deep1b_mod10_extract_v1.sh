#!/bin/bash
set -uo pipefail
root=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031
run="${root}/deep1b-100m-v1"
source_dir="${root}/data/BigANN/deep/1000000000"
output_dir="${root}/data/BigANN/deep/mod10-100000000"
/usr/bin/python3 -u "${run}/benchmark/extract_deep1b_mod10_v1.py" \
  --source "${source_dir}/base.1000000000.fbin" \
  --source-manifest "${source_dir}/manifest.json" \
  --output-dir "${output_dir}" \
  --reserve-gb 40
status=$?
printf '%s\n' "${status}" > "${run}/extract.exit"
exit "${status}"
