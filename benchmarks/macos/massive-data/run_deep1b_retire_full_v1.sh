#!/bin/bash
set -uo pipefail
run=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031/deep1b-100m-v1
/usr/bin/python3 -u \
  "${run}/benchmark/retire_deep1b_full_after_mod10_v1.py"
status=$?
printf '%s\n' "${status}" > "${run}/retire.exit"
exit "${status}"
