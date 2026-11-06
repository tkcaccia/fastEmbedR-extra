# Public multicore CPU full-graph UMAP

2 November 2026. Isolated package source:
`in-progress/cuda-graph-options-20261102`, based on fastEmbedR
`4571fe483e29a528b4b837b5c9f5cefe509fac7b`.

`umap()` now accepts `cpu_update = "synchronized"` for prepared full-graph
UMAP. It passes the option to the existing lower-level optimizer. The default
remains ordered, one-worker SGD. Non-full modes reject synchronized updates;
the lower-level validator rejects them on Metal or CUDA. The result reports
the selected optimizer, `parameters$cpu_update`, and effective CPU workers.
The trajectory differs from ordered SGD and must be labeled separately in
benchmarks.

On Chiamaka, the isolated candidate was installed with R 4.6.1 in the
existing CUDA-capable container. The focused public full-graph UMAP test
passed 20 expectations: a two-worker public call matched the lower-level
synchronized call exactly, reported two effective workers, and rejected
implicit multicore SGD and invalid choices. This test used CPU only.
Source style, `git diff --check`, and `tools::checkRd("man/umap.Rd")` passed.

The local and Chiamaka copies of the changed R source, test, manual, and API
document matched by SHA256 at validation. The installed native library was
`188eedbff9cca00e2627413996b84ed4b965b472d79522828a4eb6bcd87e8d9d`.
The candidate is uncommitted and has not been substituted into the active
Mac benchmark.

## MNIST70k CPU scaling pilot

Two ordered passes ran on Chiamaka's 13th Gen Intel Core i7-13700
(16 physical cores, 24 logical CPUs, 31 GiB RAM). The second pass reversed
worker order to check the first pass's warm-cache trend. Both used the same
verified 70,000-row KNN input, 2D PCA initialization, 1,588,812-edge fuzzy
CSR graph, 200 epochs, and synchronized CPU optimizer. These are fit times;
the shared graph took 0.476 seconds to construct per pass.

| CPU workers | Forward fit (s) | Reverse fit (s) |
| ---: | ---: | ---: |
| 1 | 21.187 | 21.171 |
| 2 | 11.778 | 11.792 |
| 4 | 7.070 | 6.905 |
| 8 | 4.732 | 4.569 |

All eight runs exited successfully, reported the requested effective worker
count, returned finite coordinates, and produced identical output SHA256
`4c432f79ed2bf7a503e891a087eeda83a7f0d067ac39647e4e301306ed4f953a`.
The one-to-eight worker ratio is 4.55 using the mean of each pair. Both
passes showed the same monotonic pattern, so warm-cache order did not explain
the improvement. The machine was shared and this is one dataset; the result
is a pilot, not a manuscript-wide speed claim. Additional repeated datasets,
quality checks, and stage-level resource accounting remain open.

Versioned scripts, CSVs, logs, manifests, one layout from each pass, and
verified checksums are under
`benchmarks/linux/cpu-umap-sync-20261102/evidence/`. The remaining identical
layouts and prepared graph remain in the isolated Chiamaka test directory.
The local `audit.py` independently checked both evidence manifests, exit
codes, four worker rows per pass, layout size, and output hashes.
