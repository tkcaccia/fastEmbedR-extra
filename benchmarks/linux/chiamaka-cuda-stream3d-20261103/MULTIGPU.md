# CUDA coordinated 3D t-SNE implementation check, 3 November 2026

This is development evidence, not an HPC result or a benchmark measurement.
The isolated package candidate is at
`fastEmbedR/in-progress/cuda-multigpu-3d-20261103`.

The candidate extends the existing NCCL t-SNE optimizer to three
coordinates: gradient reduction and layout/state gathering use a
dimension-aware row stride; each device updates its owned rows; the three
coordinate sums are reduced across devices before centering. The graph
remains file-backed in this route, so this code must **not** run on the HPC.

Chiamaka build area: `/tmp/fastembedr_cuda_multi3d_20261103`.
The 29 October Singularity image built this source with CUDA and NCCL
enabled and `R CMD INSTALL` returned 0. The installed native library is
`f7f6767fc6b58376b19c09bb348f108fe22f0172061ee337c1ff1eea396aa16f`
(SHA256). The staged native source hashes are:

- `src/embedding_cuda_kernels.cpp`:
  `3ccf22eeba7fb528a6d611d40b72c65eb2ef281c902c99d1e18eb8ea1cbc4c22`
- `src/massive_matrix.cpp`:
  `a0e9525ea3959e9ea1b3ba5f978475d2fe60e53e40c573abc377e700551d1636`

The CUDA device identity/planner test file passed with the new 3D
two-device case (38 assertions). The test explicitly confirms three
dimensions, two selected devices, and physical GPU identities. The
source style check, R parse, and `git diff --check` passed locally.

The new two-GPU 3D fit/checkpoint test in
`tests/testthat/test-massive-graph.R` has **not** run: Chiamaka exposes
one GPU, the UCT HPC GPU campaign is paused, and the prior Hugging Face
US$2 cap is nearly exhausted. The one-GPU 3D checkpoint and 2D
regression passed in the corrected idle-only Chiamaka retry; see
[`README.md`](README.md). No Bora process was touched.

Do not call coordinated 3D validated or use it in the manuscript until
the two-GPU test passes on a current build and output quality is checked.
