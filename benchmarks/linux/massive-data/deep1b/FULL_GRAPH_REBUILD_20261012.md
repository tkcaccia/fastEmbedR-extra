# Deep1B full-graph rebuild

**Superseded.** This historical plan includes 100M jobs. Use the
[20M-capped campaign](README_20M.md) for new submissions.

## What the October 11 results actually measured

The `scale10m`, `boundary`, and `billion` t-SNE/UMAP cases used
`massive = "landmark"` in `../run_scaling.R`. Their case tables requested
10,000 landmarks for 10M, 100M, and 1B rows. Rasterizing every projected
row did not make those fits full-graph. No audited Deep1B full-graph
t-SNE or UMAP result exists in these campaigns. Do not use their plots
to illustrate full-graph fitting.

The 100M landmark UMAP cases failed after output because
`massive_projection_complete()` multiplied integer row and neighbor
counts, overflowing R's integer range. The package now calculates file
sizes in double precision; the regression test uses a 100M by 30 graph.
The 100M Leiden cases were rejected by the free-disk guard. The 1B
landmark UMAP case succeeded, but it is not evidence for 1B full graph.
The October campaigns left approximately 183 GiB of binary results,
mostly repeated 100M landmark KNN files and per-campaign image links.

## Replacement experiment

`submit_deep_rebuild.sh` submits Deep1B CPU and CUDA cases without waiting
for an L40S job before starting CPU work. The first 1M rows of the window
start at source row 1,000,001 for both classic and full-graph routes.
The same row window and seed are used for PCA, UMAP, and t-SNE. The
classic path materializes those 1M rows as an R double matrix; the
full-graph path reads the input in chunks. This is a memory-boundary
comparison, not an assertion that all optimizer defaults are identical.

| Rows | Classic | Full graph and Leiden | Independent PCA |
| ---: | --- | --- | --- |
| 1M | CPU and CUDA | CPU and CUDA; CPU Leiden | Included in both |
| 10M | No | CPU and CUDA; CPU Leiden | CPU and CUDA |
| 100M | No | CPU t-SNE and UMAP/Leiden, then CUDA | CPU and CUDA |

Each successful embedding fit writes stage timings, process peak RSS, a
bounded quality sample, an all-row grayscale PNG, and audit evidence.
CPU full-graph fits also run Leiden on the same fuzzy graph and write
community count, modularity, and a separately labeled community-size
plot from 10,000 randomly sampled rows. Embedding points are never
colored by these inferred communities. CUDA jobs record per-device
sampled VRAM. Binary layouts, labels, and graph work files are removed
after scoring and rendering. Input `.fbin` files are never removed.
The plot subtitle says "all output rows"; only `_fullgraph` and
`_classic` case names claim how the layout was fitted.
The shared graph job attempts t-SNE and UMAP separately. If either
fails, the case audit fails while the successful method's metrics and
figure remain available for diagnosis.

The current fuzzy-graph sorter budgets 96 bytes per directed edge.
The preflight requires about 483 GB for 100M by 30-neighbor full graph,
plus a 20% free-space margin. This launcher does not submit 1B jobs.
A 1B full-graph claim requires a more disk-efficient graph construction
method or a larger allocation, followed by a completed run. No
landmark fallback is allowed.

## Validation and launch

The local 2,000-row smoke input passed classic and file-backed
full-graph PCA, UMAP, and t-SNE on CPU. On Chiamaka, the current
container passed all three full-graph methods on CPU and CUDA and the
classic CUDA fit on the same small input. This is a functional smoke,
not evidence that 1M-100M jobs have completed. The tested image SHA256
was `0925105c3113c60225de70f948ad059dbcbd60ce3c4bccdd6286a366ab3131d8`.
It contains faissR 0.99.52 but predates the projection-size repair.
Rebuild `singularity/fastembedr_cuda.sif` with that fix before rerunning
the landmark benchmarks or claiming one final source identity. The
full-graph runner does not use the repaired landmark projection path.
Copy this suite and the shared `visualization/render_full_layouts.R`
to the HPC. Then submit:

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/massive-data/deep1b/submit_deep_rebuild.sh
```

The script reads `myquota` on the submitting node. If that command is
unavailable, set `DEEP1B_QUOTA_FREE_BYTES` explicitly. Inspect the
printed `jobs.tsv` ledger. The 100M CPU UMAP/Leiden and t-SNE runs are
separate jobs, followed by the CUDA 100M runs. This avoids concurrent
large graph-sort workspaces and isolates optimizer failures. These
barriers use `afterany`, so a failed predecessor does not prevent the
next case from running. The 1M and 10M CPU jobs never depend on an
L40S job. PCA jobs are independent of graph construction, so a graph
failure does not erase the PCA comparison.

The October 11 evidence was reviewed before cleanup. It was diagnostic
only and is not a source for manuscript figures or performance claims.
Its local and HPC `fastEmbedR-results/massive-data` trees were purged
on October 12; the BigANN source files and unrelated result trees were
left in place.
