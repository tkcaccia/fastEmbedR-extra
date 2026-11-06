#!/bin/bash
set -Eeuo pipefail
root=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-threadpool-c288af6-20261106
for pair in \
  baseline:e6a40a611ff636073ee2c5b40d4c41cd66bca4c324750223087857b673a54fb3 \
  candidate:5309c44f502820ffdf4b0a430b1d58ea376789e20d6f6049071ed26bfb1c727d
do
  name=${pair%%:*}
  expected=${pair#*:}
  archive="$root/$name/fastEmbedR_0.1.tar.gz"
  actual=$(shasum -a 256 "$archive" | awk '{print $1}')
  [[ "$actual" == "$expected" ]]
  mkdir -p "$root/$name/library"
  export R_LIBS_USER="$root/$name/library:/Users/silvanopiazza/Documents/Stefano/data/Rlib"
  /Library/Frameworks/R.framework/Resources/bin/R CMD INSTALL \
    --preclean --library="$root/$name/library" "$archive"
done
printf '%s\n' THREADPOOL_BUILD_PASS
