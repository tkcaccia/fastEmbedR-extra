# Resident coordinated CUDA t-SNE development check

An isolated package candidate at
`fastEmbedR/in-progress/cuda-multigpu-3d-20261103` now connects the
package's in-RAM symmetric KNN affinities to the existing NCCL CUDA
t-SNE optimizer. `tsne_knn()` and `tsne()` accept two to four explicit
CUDA devices for resident 2D/3D fits. KNN affinities stay in host RAM;
layout, gradients, gains, and updates stay on the GPUs; output returns
as an R matrix. This route does not read, map, or stream algorithm data
from SSD. It is distinct from `massive_tsne_optimize()` and is the
candidate route for the HPC no-file-backed rule.

Chiamaka built the candidate in
`/tmp/fastembedr_resident_multi_20261103` with CUDA and NCCL enabled;
`R CMD INSTALL` returned 0. The installed native library SHA256 is
`16759e7e6011e6531f3cc6c3e3055778b2b42fb0f3132f4489b85ed2aef11dd6`.
The staged `src/tsne_neighbors.cpp` hash is
`863f757b05993334e2eff7f93c74f9e2074baa60e9ad9239b911a0701b225bb4`;
the generated `src/RcppExports.cpp` hash is
`299fec6cdba80bd69819c50b6f2c4c7a0ac28e18656b754af62ba529d5c5b3c8`.

The focused, CPU-only mocked public dispatch test passed eight
assertions against that installed package: both `tsne_knn()` and
`tsne()` reached the coordinated native entry point, returned device
IDs and UUIDs, and rejected a CPU-labelled device request. Source style,
R parse, generated Rcpp export identity, and `git diff --check` passed.

The final candidate was rebuilt on Chiamaka in
`/tmp/fastembedr_resident_multi_final_20261103`; `R CMD INSTALL`
returned 0. Its native library SHA256 is
`bfff42e5f003f66e317d6656d3bfa7bfadabca3d1c7c9e6327624548269dcf6a`.
The staged `src/tsne_neighbors.cpp` SHA256 is
`1de91a114fdd0d2222d87558af96f6e2257016de6497354bcda03084d4ca3b31`.
The test launcher explicitly selected the rebuilt library. The focused
resident public dispatch tests passed 9 assertions, and the CUDA device
identity suite passed 38 assertions. No GPU calculation was performed
in these mocked tests.

This is **compiled and dispatch-checked, not device-validated**.
After changing worker-thread errors to native C++ exceptions, the exact
current candidate was rebuilt at
`/tmp/fastembedr_resident_multi_final2_20261103` with exit 0. The
native library SHA256 is
`f399f36ddb5f7c9ece03a9f03ed1c2ed04048b13c63995929555da0369ff20b1`;
`src/tsne_neighbors.cpp` SHA256 is
`1eb3c327757bf5f5e9443b7305018244af452b299efe8e3f87d8dc449068d228`.
The same 9 dispatch and 38 device-identity assertions passed against this
exact installed package. These tests do not exercise two GPUs.
The 3D FFT CPU regression file passed 23 assertions with the test environment
parented to the installed package namespace. Metal and CUDA cases skipped
because the compilation-only container was run without device passthrough.

The combined t-SNE and UMAP candidate was built exactly at
`/tmp/fastembedr_resident_combined_20261103` with exit 0. Its installed
native library SHA256 is
`32e84a6322d25e4b7034294379c4bc644ee9755854ed5d71c586ada6174a13f5`.
The strict runner passed 9 resident t-SNE dispatch, 11 resident UMAP
dispatch, and 38 CUDA device-identity assertions. The CPU 3D FFT file
passed 23 assertions; 9 accelerator cases skipped without device
passthrough. The real two-GPU numerical check remains pending.
The strict test log is `combined_tests.log` (SHA256
`eccb4cef27a5234818a0519fca5ab79d4fb882c56a6393c24632fb8b1dcbec14`);
`combined_tests_exit` records exit code 0.
Chiamaka exposes only one GPU. The UCT HPC GPU campaign is paused;
no HPC job was submitted. A real two-GPU comparison against the
single-GPU optimizer, 2D and 3D quality checks, and memory/cleanup
audits must pass before this route enters a benchmark or manuscript.
