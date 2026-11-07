# Resident comparator qualification for package main 535d071

This is a separate competitor lane for the eleven-dataset resident benchmark.
The archived JSS comparator controller cannot run on UCT HPC because it also
launches file-backed scientific work. This lane must reject file-backed input
and execute one reviewed case per compute allocation.

The first gate checks available comparator packages in the existing
`535d071` image. It does not fit any data or require another Singularity
build. Candidate methods are Rtsne, FIt-SNE, openTSNE, uwot, R umap,
umap-learn, and RAPIDS cuML. Record the input type and conversion time
separately from each fit; fastEmbedR results use the source `float32` object.
Compare only cases with the same rows, preprocessing, output dimensions,
quality sample, and documented algorithm controls. Preserve unsupported or
failed methods as such rather than silently substituting another algorithm.

Compute-node dependency probe 1606763 completed: Rtsne, FIt-SNE wrapper and
binary, uwot, R umap, openTSNE, umap-learn, and cuML are present in the
existing image. The next gate is a four-method, 2D COIL20 CPU4 pilot for the
R comparators. Its source remains a development candidate until all four
methods and the independent audit pass. It uses rank-30 float32 preprocessing;
conversion to the competitors' double input is measured separately from fit.

The source-locked COIL20 CPU4 pilot array 1606770 completed all four R
comparators. Independent compute audit 1606773 passed **4/4**; the exact
report and raw metrics are under `evidence/`. One seed is development evidence,
and the methods do not all use identical optimization schedules.

| Method | Fit seconds | Trustworthiness | Label accuracy |
|---|---:|---:|---:|
| Rtsne | 0.650 | 0.9822 | 0.8850 |
| FIt-SNE | 2.218 | 0.9727 | 0.8717 |
| uwot | 2.119 | 0.9782 | 0.8900 |
| R umap | 4.707 | 0.9819 | 0.8767 |

The shared rank-30 PCA preprocessing took about 0.48–0.53 seconds per case
and is recorded separately. Conversion to double happened before the fit
timer. These values are not publication comparisons with fastEmbedR until
the parameter and repetition audit is complete.

The pilot's Rtsne and FIt-SNE calls requested `max_iter = 300`, which is a
**total** iteration budget. The matched fastEmbedR t-SNE cases request 250
early-exaggeration iterations **plus** 300 normal iterations. Therefore the
two R t-SNE timings above are diagnostic only and must never be placed beside
the matched fastEmbedR timings as a fair speed comparison. A compute-node
wrapper API probe 1606877 confirmed FIt-SNE exposes
`stop_early_exag_iter` and `mom_switch_iter`; its formals are preserved in
`evidence/fitsne-formals-1606877.out`. The versioned 550-total-iteration
Rtsne/FIt-SNE correction is pilot 1606879. Independent audit 1606880 passed
**2/2**. Its two cases write to distinct result folders and leave the first
pilot unchanged.

| Corrected t-SNE method | Fit seconds | Trustworthiness | Label accuracy |
|---|---:|---:|---:|
| Rtsne, 250 + 300 iterations | 0.717 | 0.9831 | 0.8933 |
| FIt-SNE, 250 + 300 iterations | 5.467 | 0.9796 | 0.9017 |

The first pilot's FIt-SNE time was 2.218 seconds with only 300 total
iterations, confirming that iteration mismatch materially changed its timing.
The corrected pilot remains one seed and does not establish a publication
speed or quality ranking.

Compute-only bridge probe 1606775 confirmed that R 4.6 in the same image can
use `/opt/conda/bin/python` through `reticulate` and import NumPy, openTSNE,
and umap-learn. The source-locked two-method COIL20 Python pilot 1606824
completed and independent audit 1606825 passed **2/2**. The R worker preserves the same
float32 source and rank-30 preprocessing; its conversion to a double matrix
and then to a Python array are measured before the fit timer. Each method
runs resident-only in one CPU allocation. With a fixed seed, umap-learn may
execute its optimizer serially despite the four-core allocation; the device
log confirms this. The worker records that limitation rather than claiming
four-core speedup.

| Python method | Fit seconds | Trustworthiness | Label accuracy |
|---|---:|---:|---:|
| openTSNE | 3.887 | 0.9834 | 0.9033 |
| umap-learn | 7.231 | 0.9791 | 0.8950 |

Raw metrics and the exact audit are under `evidence/`. These one-seed pilot
results must not enter the manuscript comparison before the parameter and
repetition review.
