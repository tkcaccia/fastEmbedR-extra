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
