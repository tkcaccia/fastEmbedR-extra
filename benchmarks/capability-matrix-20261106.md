# Capability qualification ledger, 2026-11-06

The adjacent CSV enumerates all 140 combinations of PCA, 2D/3D t-SNE,
2D/3D UMAP, Leiden and Louvain; single/multi-CPU, single/multi-CUDA,
and single Metal; resident/file-backed storage; and full/landmark fits.
Metal multi-GPU is excluded because the available Mac has one GPU.

This is an interim evidence ledger. **Unqualified** means a route may exist,
but the current evidence does not yet establish real-device correctness,
quality, memory and no fallback. It must not be reported as verified in the
manuscript. Final release classification requires each row to be verified,
failing, limited by measured resources, or not implemented, with an exact
source version and direct evidence. There are 137 unqualified and three
failing rows in this version; no row is promoted to verified from a small
pilot.

The additional failing row is resident, full-data, 2D Metal UMAP. On a fixed
5,000-row Fashion-MNIST graph with identical CPU/Metal initialization, the
paired three-seed silhouette gate failed. Detailed experiments and source
identity are in `benchmarks/macos/metal-umap-fix-20261104/README.md`.
The existing two failing rows are multi-CPU file-backed full-graph Leiden
and Louvain: tested multicore settings were slower than one core on the
measured Mac graphs. Those are performance failures, not correctness or
label-parity failures.

The new 7c68bc2 resident HPC CPU pilot and four method pilots contribute
input, backend, output, quality and memory evidence for five full-data
multi-CPU routes. The 72-case wave has been submitted but is not terminal.
These rows remain unqualified pending repeated real-data measurements,
scheduler/output audit, and graph-identity control for clustering. See
`benchmarks/linux/matched-main-7c68bc2-20261106-v1/RUN-20261106.md`.

File-backed scientific analysis is never run on the UCT HPC. Deep1B is a
fastEmbedR stress test outside the eleven-dataset competitor panel. Landmark
output must cover every input row. `cuda_multi` means one coordinated fit
across devices, not independent per-GPU fits.
