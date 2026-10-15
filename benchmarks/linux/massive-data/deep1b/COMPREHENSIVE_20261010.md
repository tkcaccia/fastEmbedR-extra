# Source-locked Deep/Turing campaign

This campaign uses the completed 1B `.fbin` files as file-backed inputs.
Its CPU and CUDA controllers are independent. They do not use the scripts
of an already-running source-locked campaign on the HPC.

## Evidence that shaped the plan

The previous copied 5M evidence showed bounded process RSS for file-backed
PCA and landmark projection, but it did not establish a full-data 1B graph
or full-data 1B t-SNE/UMAP optimization. The 5M diagnostic figures contained
only 512 points. Turing HNSW recall has also been more fragile than DEEP
despite similar dimensions. These are separate questions, not successes to
infer from one another.

## Experiments

Each dataset has its own input rows and audit. Four independent controllers
cover Deep/Turing x CPU/Ada/CUDA/L40S. Each lane runs its own pilot first.
After that pilot is audited, all independent phases and repeats in that
lane are submitted without cross-phase dependencies. Ada work never waits
for L40S work. The final audit waits for every phase audit and plot in its
own lane. A pilot structural failure stops that lane; later structural
failures are all collected by the final audit. Recall below 0.99 is kept
as a named quality gap, not silently counted as a pass.

| Stage | Rows | Main question | Repeats |
| --- | ---: | --- | ---: |
| pilot | 20,000 | Package, backend, graph and cluster smoke checks | 1 |
| scale | 1M | PCA, full KNN, landmark UMAP/t-SNE, Leiden/Louvain | 3 |
| threads1m | 1M | CPU PCA/KNN/UMAP/t-SNE at 2, 4, 8, 12 cores | 1 |
| fresh5m | 5M | Repeated timing, peak RSS/VRAM, requested 2-GPU path | 3 |
| fresh5m_3d | 5M | 3D PCA/UMAP/t-SNE finite-output validation | 1 |
| scale10m | 10M | Projection, clustering and device scaling | 3 |
| boundary | 100M | Streamed PCA and landmark projections/clustering | 1 |
| billion | 1B | File-backed feasibility and bounded-memory behavior | 1 |
| graph10m | 10M | Separate full-graph KNN diagnostic and recall | 1 |

`scale10m` reads rows 6,000,001 through 16,000,000 so the input is not
the same prefix used by 1M/5M cases. The billion-row experiments are **not**
evidence that full 1B t-SNE/UMAP or a full 1B kNN graph was fitted: those
routes use landmarks or streamed covariance as recorded in `metrics.csv`.
The 10M graph run reports observed sampled recall; a larger independent
exact-reference holdout remains necessary before claiming 0.99 recall there.

The 1M/5M/10M elapsed times have three repetitions but are not automatically
publication-grade if other users' jobs contend for the same nodes. The
manuscript should use only runs with their complete timing boundary,
hardware identity, observed process RSS, GPU memory, output validity,
and quality audit in the campaign ledger.

## Full-row figures and labels

After the first repeat's audit at each size, a separate Ada job reads the
complete `.f32` output in chunks, counts **every fitted row** into a 1600 x 1600
grayscale density image, and records `plotted_rows` in
`visual_manifest.csv`. A final visual audit checks row counts and images.
Three-dimensional fits receive XY, XZ, and YZ views.
The gray density is not a cluster or class assignment. The Big ANN Turing
and DEEP vector files contain no row-aligned semantic class column. Do not
assign class colors unless a separate verified label file, including row
identity and provenance, is supplied. Nearest-neighbor ground truth for
held-out queries is not a class label.

The renderer is a density raster because a billion individually drawn marks
cannot be distinguished at screen resolution; nonetheless every row must
contribute to a pixel count. These figures are descriptive, not label-based
quality metrics.

The pilot preflight in each lane runs the full-layout renderer smoke test
inside its pinned container before any fit can start. Its output is in
`plot_preflight.out` and `plot_preflight.err`; `preflight.ok` is written only
after the required package and plot checks pass. Stage image checks use
inode, size, and modification time. The filesystem device number is excluded
because it can differ between compute nodes for the same shared image.
Creating another hard link changes inode change time, so change time is
intentionally not part of that check.
The preflight also verifies the image SHA-256.

## HPC transfer and launch

Upload the complete `deep1b/` directory to a **new** versioned directory
under `/scratch/firenze/NN/benchmark_scripts/massive-data/`. Also copy
`visualization/` inside it and copy `run_scaling.R` to the directory root.
Do not overwrite the path used by the older campaign. Run
`submit_comprehensive.sh 3` from that versioned path. Pass `cpu` or `cuda`
as a second argument to submit only that backend. The default schedules all
four pilot controllers immediately. Each lane submits its
remaining independent stages after its own pilot audit; no repeated manual
submissions are needed. Within a phase, Slurm arrays cap simultaneous CPU
and GPU cases. The comprehensive launcher allows four CPU cases per array
by default; `DEEP1B_CPU_THROTTLE` can override this. The CPU-core scaling
cases remain serialized to avoid
self-contention in that measurement. Monitor each
`state.json` and the final `visual_audit.json`. The launcher hard-links the
image into the campaign, and each stage pins that image again. Replacing
the shared image name cannot change a running campaign, but do not edit
uploaded scripts or the pinned image while jobs are active.

Use `copy_small_results.sh` or selective rsync of metrics/audits/PNG files
when copying evidence back to a laptop. Never copy the 1B input or full
coordinate `.f32` files just to inspect manuscript figures.
