# Mac resident CPU and Metal panel from fastEmbedR main

Package commit: `afeaffc39a607c00db5899c284451c6cdbf741bb`.
The checked Mac installation is under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-release-v5-20261106`.
The source-locked runner and results are under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-afeaffc-benchmark-20261106`.
The input dimensions and digests are in `dataset-inventory.json`.

The resident full-data panel covers all 11 comparison datasets, PCA,
2D/3D t-SNE and UMAP, Leiden and Louvain, seeds 4/17/42, and one-core CPU,
four-core CPU, and one Metal GPU: 693 cases. Two COIL20 CPU/Metal UMAP
cases completed as source-locked admission pilots. The remaining 691 cases
were launched in a serial queue (PID 46249 at launch). A case runs in a
bounded child process, records quality, peak resident memory, swap, package
and input checksums, and output cleanup. The queue stops on an uncertain
cleanup, timeout, more than 1 GiB new swap, less than 100 GiB free disk, or
three consecutive scientific failures. `cases.jsonl` contains the exact
staged case JSON and queue plan.

This is the resident fastEmbedR panel. File-backed, landmark, competitor,
Deep1B stress, and additional CPU core-count lanes still require separate
controlled runs. The old stopped panel results remain preserved.
