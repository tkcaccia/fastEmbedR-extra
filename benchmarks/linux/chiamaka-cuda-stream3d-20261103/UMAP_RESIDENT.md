# Resident coordinated CUDA UMAP development check

The isolated package candidate at
`fastEmbedR/in-progress/cuda-multigpu-3d-20261103` now accepts
`devices = c(0L, 1L)` through `umap_knn()` and `umap()`.
It builds the fuzzy CSR graph in host RAM, retains the layout and
epoch deltas on two to four GPUs, and returns an R matrix with device
identity and per-device edge visits. It does not use SSD mapping or
streaming for the algorithm.

Chiamaka compiled the follow-on source in
`/tmp/fastembedr_resident_umap_20261103` with CUDA and NCCL enabled.
`R CMD INSTALL` returned 0. After an R argument fix, the installed
native library SHA256 is
`a18c7f2e83b380fc0bde5d508fe3d6aab7dd9e473562bdc11b811d8e952a1079`.
The strict test runner passed eight UMAP public-dispatch assertions,
including `umap_knn()`, `umap()`, device metadata, and CPU rejection.
The nine prior t-SNE dispatch assertions also passed. These tests mock
the two-GPU call; they do not establish GPU correctness.

A separate idle-gated one-GPU CUDA control passed 2D and 3D 32-row
UMAP fits on Chiamaka (exit 0). It checked the image, library, and
test-script SHA256 before execution and confirmed that no GPU compute
context remained. The user’s Bora job was untouched. A first gate
attempt stopped before GPU execution because the library checksum had
changed after rebuilding; both logs are retained. The final local
`umap_single_gpu.log` and `queue_umap.log` have the same SHA256 as
their remote originals:

- `f3802541b3db2babf2b2fd1b84de3321c9708746dec01455ea2c4c6fded3ccc6`
- `1a3a426282c29ab8a95660ed5c49817719c8898ca1e1e1efeaa3a17dd67a14d1`

The candidate has one additional finite-float32 weight guard after
that build. The exact current combined candidate subsequently built in
`/tmp/fastembedr_resident_combined_20261103` with exit 0. Its native
library SHA256 is
`32e84a6322d25e4b7034294379c4bc644ee9755854ed5d71c586ada6174a13f5`;
`src/embedding_cuda_bridge.cpp` SHA256 is
`912a8fc4a65db87f87fa8ebaaea43c6b92fa6800e20c69b2e6a17f0df4a5b7c6`.
The strict runner passed 11 UMAP assertions after adding a native-GPU-KNN
materialization test, plus the 9 t-SNE dispatch assertions.
Real two-GPU numerical validation remains pending. No UCT HPC job was
submitted; its GPU pause and no-file-backed rule remain in force.
