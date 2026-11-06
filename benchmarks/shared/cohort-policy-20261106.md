# Cross-platform benchmark comparability audit, 6 November 2026

The newly launched Mac and HPC source-locked resident panels use the same
input files (the HPC compute-node audit verified all 11 SHA-256 digests) and
the same fastEmbedR package commit `afeaffc`. They are **separate development
cohorts**, not directly comparable Figure 1–3 timings or quality results:

- The Mac worker applies CPU PCA to rank 30 (or one less than input width)
  before t-SNE, UMAP and graph clustering. Its PCA method fits the original
  features. It records preprocessing and fit time separately.
- The HPC worker sends the original matrix directly to every method. Its
  t-SNE defaults to 250 early-exaggeration and 500 subsequent iterations.
  The Mac worker requests 300 subsequent iterations.
- The Mac worker records embedding trustworthiness/label accuracy and
  clustering ARI/modularity. The HPC worker currently saves the fit and
  backend metadata but does not calculate the matching quality metrics.

The running source-locked jobs must not be edited. Their results can support
within-Mac and within-HPC scaling for the stated pipeline, with the stated
limits. A new versioned, matched-settings cohort is required before any
cross-platform speed or quality comparison in the manuscript.

The matched cohort contract is: identical input digest, PCA preprocessing
rank/centering/seed or an explicit no-preprocessing choice, neighbor count,
t-SNE perplexity/affinity support/iteration schedule, UMAP settings, graph
construction, output dimension, seed, and quality sample. Record input
loading, preprocessing, graph construction, fit, quality and output writing
separately. Require backend and worker-count evidence and reject silent
fallbacks. Preserve a case/result identity that prevents mixing versions.
HPC cases must remain resident in both input and algorithm state; file-backed
and SSD-streaming methods run only outside the HPC.
