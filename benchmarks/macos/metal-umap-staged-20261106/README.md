# Resident Metal UMAP quality repair, 6 November 2026

## Scope

Isolated package candidate:
`in-progress/cuda-multigpu-3d-20261103`. Original package checkout and
active benchmark inputs were not modified. This is development evidence,
not a JSS benchmark cohort.

The failing fixed-graph Fashion-MNIST 5,000-row 2D quality gate came from
concurrent optimizer dynamics. The CPU ordered (one-thread) update achieved
silhouettes near 0.21 while CPU with at least two threads and the original
Metal atomic update were near 0.19. CSR edge filtering and degree truncation
did not explain the gap. Metal truncated zero edges in the measured graph.

The repair uses one CPU thread for the first half of the resident 2D UMAP
optimization epochs, then continues the same global epoch schedule with the
native Metal atomic optimizer. Both `umap_knn()` and one-call `umap()` use
this shared route. The result records `metal_cpu_warm_epochs`,
`metal_gpu_epochs`, and `metal_optimizer_pipeline`. Resident 3D Metal UMAP
continues using the native Metal optimizer for all epochs. The file-backed
Metal UMAP route is separate and is not qualified by these tests.

## Device and quality results

All tests ran on Silvano's Mac under
`/Users/silvanopiazza/Documents/Stefano`. The final isolated Mac source
archive is `fastEmbedR-metal-stage-api-v3-20261106/source_api_v3.tar.gz`,
SHA256 `50472543d6036e80ec1e76f5ebf87e5b2d76253f4760d756b838949591fb7ba4`.

The 400-epoch direct fixed-graph check used Fashion-MNIST and MNIST,
5,000 rows each, the same CPU-prepared 30-neighbor graph and initialization,
seeds 4, 17 and 42, and 20 Metal repetitions per dataset/seed. The
acceptance rule was Metal sampled silhouette at least CPU one-thread
silhouette minus 0.01. All 120 repetitions passed; the worst difference
was -0.009017184. The source-locked test is `repeat_gate_200x20.R`
(SHA256 `caed22fc3f2d04cb54589d0a2f4e3a7851083f8bbc2a1b3e23edfa03c47104dd`);
results are `repeat_gate_200x20.log` in `fastEmbedR-metal-staged-20261106`.

The prepared public API was then checked at its 500-epoch policy with
250 CPU and 250 Metal epochs. Scores below are average sampled silhouette
on the same fixed 30-neighbor graph and initialization:

| Dataset | Seed | CPU one thread | Staged Metal | CPU seconds | Staged seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fashion-MNIST | 4 | 0.16602 | 0.19013 | 2.841 | 1.820 |
| Fashion-MNIST | 17 | 0.17614 | 0.18076 | 2.762 | 1.812 |
| Fashion-MNIST | 42 | 0.19566 | 0.19611 | 2.826 | 1.799 |
| MNIST | 4 | 0.34196 | 0.35700 | 2.644 | 1.719 |
| MNIST | 17 | 0.35683 | 0.36165 | 2.645 | 1.713 |
| MNIST | 42 | 0.35228 | 0.36537 | 2.654 | 1.724 |

Source: `fastEmbedR-metal-stage-api-20261106/public_api_gate_v2.R`
(SHA256 `d3a52cef455413c3f724610454e015b857002ac1787d6a715fa66d8098ce8c86`)
and `public_api_gate_v2.log`. These times cover the fixed-graph optimizer
call, not KNN search, graph construction, or a full public fit.

The isolated v3 package built on macOS arm64. The full `testthat` UMAP
filter passed, including the new 2D stage metadata, one-call metadata,
CPU epoch-resume equality, and existing 3D Metal tests. Five CUDA-specific
tests skipped because this Mac has no CUDA device. Logs are
`fastEmbedR-metal-stage-api-v3-20261106/build.log`, `metal_tests.log`,
and `all_umap_tests.log`. Local source style and `git diff --check` passed.

The final v4 revision additionally corrected the 3D optimizer metadata and
tests that it reports zero CPU epochs. Its source archive SHA256 is
`f0a50ce64544a1cb5050eb2a453f56ef117d59e90164f34b0dc004d2f798d737`.
The v4 package built successfully and its full UMAP test filter passed
(`fastEmbedR-metal-stage-api-v4-20261106/build.log` and `umap_tests.log`).

A separate one-call Fashion-MNIST 5,000-row check used each backend's native
KNN search and seed 42. CPU silhouette was 0.2048183 in 3.092 seconds;
Metal silhouette was 0.2120267 in 2.082 seconds. The Metal result reported
250 CPU warm epochs and 250 Metal epochs. The script and log are
`fastEmbedR-metal-stage-api-v3-20261106/onecall_fashion.R` and
`onecall_fashion.log`. These are one-seed development measurements.

## Limits

The 2D Metal route is an explicit hybrid optimizer. The evidence does not
establish an all-GPU Metal quality fix. Evaluate full one-call fits,
additional datasets, memory, and large resident and file-backed cases
separately before making publication-scale performance claims.
