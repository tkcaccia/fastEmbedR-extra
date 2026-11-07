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
