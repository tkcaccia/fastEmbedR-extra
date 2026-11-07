# ImageNet float32 input diagnostic on Silvano's Mac

The source-locked `afeaffc` resident panel stopped at ImageNet because its
worker converted the 1,281,167 × 1,024 float32 input to a double matrix
before calculation, reaching R's 16 GiB vector limit. This versioned
diagnostic changed only that conversion, kept the same input, package,
Metal PCA method and seed 42, and wrote a separate output under Stefano.

The case completed with exit 0 and clear process-group cleanup in 27.453
seconds. It processed all 1,281,167 rows, recorded the Metal backend and
native MPS engine, peaked at 11,191,140,352 bytes resident memory, and
left system swap unchanged at 7.69 MiB. The fit stage took 1.049 seconds.
Its output and logs are preserved at
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-imagenet-float32-diagnostic-20261107`.

This isolates the benchmark worker's unnecessary double conversion for
Metal PCA. It does not certify ImageNet t-SNE, UMAP or clustering, nor any
full-panel result. The later `535d071` Mac panel uses a new worker and
source version; do not pool this diagnostic with that cohort.
