#!/bin/bash
set -Eeuo pipefail
root=/Users/silvanopiazza/Documents/Stefano/fastEmbedR-metal-ordered-1846203
expected=9032793bf88a72a623fe0a95ccf48bcb745df9dbc2d1b2395d4b1aeda280e466
archive="$root/fastEmbedR_0.1.tar.gz"
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
[[ "$actual" == "$expected" ]]
mkdir -p "$root/library"
export R_LIBS_USER="$root/library:/Users/silvanopiazza/Documents/Stefano/data/Rlib"
/Library/Frameworks/R.framework/Resources/bin/R CMD INSTALL \
    --preclean --install-tests --library="$root/library" "$archive"
/Library/Frameworks/R.framework/Resources/bin/Rscript -e \
    'stopifnot(startsWith(find.package("fastEmbedR"),
        "/Users/silvanopiazza/Documents/Stefano/fastEmbedR-metal-ordered-1846203/library"),
        is.function(fastEmbedR:::knn_embed_metal_csr_cpp))'
echo METAL_ORDERED_CANDIDATE_BUILD_PASS
