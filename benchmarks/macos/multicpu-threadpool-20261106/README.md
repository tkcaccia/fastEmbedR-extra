# File-backed clustering reusable-worker candidate

The earlier 65,536-to-262,144 edge batch-size experiment was already tested
and made Mac clustering slightly slower; see
`benchmarks/macos/multicpu-fullgraph-20261104/PERFORMANCE_FOLLOWUP.md`.
This candidate instead reuses CPU worker threads across proposal batches
inside one file-backed Louvain scan segment. The ordered move commit, stale
neighbor-label check, graph scan, and bounded scratch cap are unchanged.
Leiden calls the same Louvain level. The worker group catches exceptions,
joins threads on all exit paths, and never calls R from a worker thread.

Package base: `7c68bc2a48ff3f98d07f216db9601047951827fd`.
Isolated candidate: `c288af69e41d24fc936494fa64053d89fcdcdf27`.
The source patch is preserved at
`development/candidates/fastEmbedR-multicpu-threadpool-7c68bc2-to-c288af6.patch.gz`
(SHA-256 `665a485b831ea9c9bf4014367c699bf333ef61402b52a1e0dd88a26fc6eedd39`).
The modified `src/massive_matrix.cpp` has SHA-256
`c29e5683e83189d588a517cc7e8a28555deb0b098446352de527f20ab17590bc`.
Linux C++17 syntax compilation passed, and the patch applies cleanly to the
base source. This is **not** a real-device performance or package test.

Checksum-verified source archives and paired-test scripts are staged under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-threadpool-c288af6-20261106`.
Baseline archive SHA-256:
`e6a40a611ff636073ee2c5b40d4c41cd66bca4c324750223087857b673a54fb3`.
Candidate archive SHA-256:
`5309c44f502820ffdf4b0a430b1d58ea376789e20d6f6049071ed26bfb1c727d`.
Both checksums were verified after transfer. The active source-locked Mac
panel is still running, so **no build or scientific fit has started** for
this candidate.

After the panel terminates successfully, `build.sh` installs the two
archives in separate Stefano libraries. `run_pairs.py` calls the public
`graph_cluster()` API on the existing 100k×30 and 50k×200 file-backed
graphs, comparing one, four, and eight CPU workers for Louvain and Leiden
across three paired repetitions. It alternates source order, records elapsed
fit time, process peak RSS and system swap, and requires exact membership
SHA-256, community count and modularity parity for every pair. It stops and
preserves logs on a failure. A speedup and memory/quality gate must be
measured before integration; this staged source is not on package main.
No file-backed scientific work will run on UCT HPC.
