# Full-row real-data comparison

This suite compares the resident float32 and experimental file-backed
fastEmbedR calls on **all rows** of flow18 (1,000,021 x 11), ImageNet
(1,281,167 x 1,024), and FlowRepository (5,220,347 x 32). The common
`.f32` input is prepared once from the original RData object. That
conversion necessarily loads the RData into host RAM and is timed in its
own Slurm job; it is not included in either fit time. The classic call
loads the entire `.f32` matrix during its measured process. The file-backed
call uses `massive_matrix()` with `massive = "out_of_core"` for PCA and
`massive = "landmark"` for t-SNE, UMAP, and Leiden clustering. Neither
route is described as a matched algorithm for the embedding methods.

Cases include one and eight CPU workers, one L40S, and a two-L40S
file-backed run. The classic API does not accept `devices`, so classic
two-GPU cases are recorded as unsupported, not silently rerouted.
Each fit gets a two-hour limit and only one repetition. GPU methods are
bundled within one allocation per dataset/route/device count to reduce
L40S queue overhead; CPU cases are independent array tasks with another
30 minutes reserved for scoring and plotting. GNU `time -v`
records full command wall time and peak process RSS; CUDA runs sample
per-process GPU-memory peaks. The fit times exclude subsequent quality
scoring and plotting. `audit.json` and `all_cases.csv` distinguish
success, timeout, OOM, and incomplete metric or image evidence.

Every successful PCA, t-SNE, and UMAP layout is scanned in full and
rasterized to `plot_density.png`. If original source labels exist,
`plot_source_labels.png` colors each occupied pixel by the dominant
**source** label among the 23 most frequent labels and an `Other` group,
with `source_label_legend.csv`; no clustering output is used to color an
embedding. `visual_manifest.csv` confirms that all fitted
rows contributed. Quality is evaluated on the same deterministic 2,048-row
subset for each route; it is *not* a full-data quality metric.

`submit.sh` queues preparation and all CPU/GPU lanes independently by
dataset. `matched_pairs.csv` contains only successful resident/file-backed
pairs at identical dataset, method, backend, and core count, with speed,
RSS, VRAM, trustworthiness, and neighborhood preservation side by side.
The audit also plots wall time, peak RSS, peak VRAM, and trustworthiness
for successful embedding cases (`comparison_*.png`).
GPU2 and
landmark clustering remain separate rows in `all_cases.csv`.

This suite needs the existing JSS `common/common.R`, `run_scaling.R`,
`deep1b/gpu_memory.py`, and a source-locked `fastembedr_cuda.sif` on the
HPC. The launcher refuses missing dependencies; it never builds or
replaces the image.
