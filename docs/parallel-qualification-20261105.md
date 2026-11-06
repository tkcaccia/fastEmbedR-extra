# Parallel qualification and API audit, 5 November 2026

This is a development plan, not a release or manuscript result. Preserve source-locked historical campaigns and original user files. Use one reviewed candidate commit and a distinct immutable build per platform.

## Current admission findings

- UCT L40S pilot 1570379 failed before scientific calculation: the launcher could not map the two assigned Slurm GPU indices to UUIDs. The saved log records image verification and `pilot_fail`; it contains no `child_started`. Diagnose Slurm/CUDA-visible index mapping with a separately versioned allocation-only probe, qualify cleanup, then rerun one resident pilot. Do not submit a GPU benchmark until that gate passes. Never perform file-backed science or a large image checksum on the login node.
- Silvano's Mac has a stopped historical audit waiter PID 20955. Leave it and its partial results untouched. New tests go in separate versioned directories under `/Users/silvanopiazza/Documents/Stefano`. Metal is single-GPU.
- Hugging Face two-A10G persistent clustering worker v3 finished synthetic parity tests. Its controlled memory-pool fixture is not a physical over-VRAM graph test. Verify remaining user-approved billing headroom before another paid job.

## Three concurrent lanes

| Lane | Development checks | Qualification gate |
| --- | --- | --- |
| Mac: CPU/Metal | Fixed-input paired full and landmark PCA, 2D/3D t-SNE/UMAP, Leiden/Louvain; 1/2/4/8/16 CPU workers; file-backed parity, checkpoint/resume, peak RAM/swap and SSD I/O. Focus first on Metal UMAP Fashion quality and multicore clustering scaling. | No unexplained backend substitution; quality thresholds fixed before inspection; Metal speed measured against same Mac CPU; effective workers recorded. |
| Hugging Face: CUDA | Two A10Gs for correctness; four L4s for dynamic communicator and partitioning; consider a short eight-L40S smoke only after reviewed eight-device code and billing check. Compare one vs multiple devices, physical VRAM per GPU, real-data clustering/embedding quality, failure cleanup and restart. | All assigned devices work; no state that must fit one GPU when pooling is claimed; physical over-combined-VRAM claim requires a real graph larger than combined VRAM, not only an artificial pool limit. |
| UCT HPC: resident CPU/L40S | Continue safe resident CPU checks. Repair GPU identity mapping in a new launcher, qualify one short resident L40S pilot and lifecycle cleanup, then 1/2/3 L40S comparison datasets and scaling. | Exact source/image/input identity, scheduler outcome, owned-process and assigned-context cleanup, no SSD-streaming scientific work. |

## API/repository audit

1. Treat `pca()`, `tsne()`, `umap()`, and `graph_cluster()` as the four analysis entry points. Keep data descriptors and genuine graph-preparation helpers public; make optimizer stages internal. Preserve compatibility only when documented and tested.
2. Audit every exported function for a caller, Rd/reference page, vignette example and backend failure contract. Compare candidate NAMESPACE with GitHub main and the deployed GitHub Pages site; publish only a reviewed release commit.
3. The current isolated candidate exports 31 functions including 15 `massive_*`; GitHub main still publishes the older broad API. The companion audit lists 42 historical benchmark R scripts calling newly internal stages. Classify each as immutable archived evidence or an active runner to migrate; do not silently rewrite source-locked experiments.
4. For each active benchmark, verify package/image/dataset hashes, public API call, exact row count, backend/device identity, quality, timing, peak RSS/VRAM, checkpoint and failure accounting. Rebuild vignette, reference manual and pkgdown; check links and examples against the installed package.

## Billion-row decision gate

Do not infer H200 runtime from A10G/L4/L40S clock speeds. First remove four-device limits throughout dispatch, native kernels, communicators and checkpoint metadata; partition graph, layout and optimizer state rather than replicating an oversized state or owning repulsion on one GPU. Audit 64-bit edge counts and bounded memory at every stage. Run representative 1M, 10M and 100M full-row Deep1B tests where permitted, then fit stage-specific time, RAM, VRAM and scratch models with uncertainty. An eight-H200 run is the final confirmation, not the development machine. On UCT HPC, the scientific calculation must be resident in RAM/VRAM.

## Agreed release boundary

Stefano selected the full one-billion-row, no-landmark Deep1B fit as a separate scale milestone. The next release gate is the Implementation Brief's documented matrix of supported PCA, 2D/3D t-SNE, 2D/3D UMAP, Leiden and Louvain routes through four main analysis calls, with real-device quality, memory, lifecycle and benchmark evidence. Each requested combination must have a verified success or an explicit, specific unsupported/resource outcome. The 1B milestone retains a measured resource model and a staged plan; it does not block the next release.
