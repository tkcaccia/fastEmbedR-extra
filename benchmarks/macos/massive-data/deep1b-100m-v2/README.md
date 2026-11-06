# Deep1B 100M Mac queue v2

Historical status: this queue exited before any 100M calculation because
the earlier 11-dataset panel stopped at the USPS quality audit. The
active continuation is documented in `../deep1b-100m-v3/README.md`.

The Mac campaign lives entirely under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031`.
The verified `base.mod10.100000000.fbin` contains original one-based
Deep1B rows satisfying `i %% 10 == 0`, in original order. It has
100,000,000 rows, 96 float32 columns, and SHA-256
`259e5ed58e0218790bec8e8514c011f39bfd839c012d8d818d9106773ffeac94`.
The full 1B source was removed after independent source and subset
checks; `deep1b-100m-v1/full_source_retirement.json` is the evidence.

The source-locked v1 queue waits for the audited 11-dataset panel. Its
smoke test will reject raw KNN distances passed to the global UMAP fuzzy
sort. Do not edit or stop that active queue. This versioned v2 queue
waits for a v1 `smoke_fullgraph,failed` result, then reuses the verified
subset and v1 package installation. It converts KNN distances to
directed UMAP memberships before the global fuzzy sort, both in the
smoke test and the 100M stages. It stops on any other v1 failure.

The v2 controller was queued on the Mac. Each stage checked
source hashes, the input file timestamp, the absence of another R
worker, and at least 200 GiB free. It records guard and disk evidence.
The controller never restarts the Mac, retries a failed stage, or
submits HPC work. If it stops, preserve its results and create a new
version for any correction.
