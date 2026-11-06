# CUDA clustering implementation qualification

The isolated package candidate at
`fastEmbedR/in-progress/cuda-multigpu-3d-20261103` adds experimental
single-GPU file-backed Louvain local moves and Leiden refinement. Its native
CUDA kernels receive bounded CSR chunks from SSD; the community state stays
on the GPU. CPU code contracts graph levels and audits modularity and Leiden
connectivity. These routes are for Chiamaka development, **not UCT HPC**.

The combined CUDA/NCCL package build on Chiamaka returned exit 0 on
2026-11-03. Its installed library SHA256 is
`bf43623737bbd520293632af085b19208195c5da8b0a60f5296c861368c4ca8d`.
The build log SHA256 is
`6b248e27c3d7e6919b903075954c306d7108e68f49b0f01b2b6a87339ae655cd`.

Installed-package CPU-only tests passed 11 streaming-cluster dispatch,
12 resident PCA, 11 resident UMAP, 9 resident t-SNE, 38 CUDA device-identity,
48 Leiden regression, and 69 Louvain regression assertions. The corrected
combined test log SHA256
is `d8605d7f1e1be2645aeca290ecda07172d73ef1e2300707d28ac52c6df3d7838`.
The Louvain regression log SHA256 is
`a9d48f2f6ecdec3a6b09df96cce5011efd324eead38219083e30c5a478616ace`.
One Metal-only Leiden test skipped on Linux. Source style and
`git diff --check` passed.

The numerical CUDA checks are queued on Chiamaka and run only after its GPU
is idle. An existing Louvain probe runs first; a resident graph-cluster and
file-backed Leiden probe follows serially. Both require the expected GPU UUID,
three idle checks, and have a 120-second calculation timeout. Bora is active
on the GPU, so **no numerical CUDA qualification result is claimed yet**.

The UCT HPC GPU campaign remains paused. No file-backed HPC job was submitted.

## Resident multi-GPU clustering candidate

The public `graph_cluster(..., backend = "cuda", devices = c(0, 1),
n_runs = 2)` route now runs independent, resident Louvain or Leiden starts
on two to four CUDA devices in parallel and selects the best modularity.
It does not split one partition across GPUs, and it creates no SSD graph or
optimizer files. Unsupported combinations fail explicitly. This is the
relevant graph-clustering route for any future HPC GPU benchmark.

The source archive SHA256 is
`eca2f5265dccdd1e0af0f3c083fef4c64815f34514ad546575ee7e9057e97bfc`.
Chiamaka's CUDA/NCCL package build returned exit 0; the installed library
SHA256 is `aafbc94359f813773f5427853e242e00b11b4aa6230faed308f3f14b622389df`.
The build log SHA256 is
`de71665f8cfa6902b383a91c801c773c2b7f05b797b684ba4a19c443165ef036`.
Installed-package tests passed 7 multi-GPU graph dispatch, 11 streaming
clustering dispatch, 12 resident PCA, 11 resident UMAP, 9 resident t-SNE,
38 CUDA device identity, 48 Leiden, and 69 Louvain assertions. The test
log SHA256 is
`73c95d2eceaf81abb1a2aac27eee685b9ea3eaa4c7e2d02e66365bead3d5c6bb`.
Real two-GPU numerical validation remains pending; Chiamaka has only one GPU,
and the UCT HPC GPU campaign is paused.
