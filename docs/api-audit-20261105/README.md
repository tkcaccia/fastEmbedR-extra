# Public API audit, 5 November 2026

The four analysis entry points are `pca()`, `tsne()`, `umap()`, and
`graph_cluster()`. `graph_cluster()` accepts resident graphs and matrices,
file-backed full graphs, and resident or file-backed landmark requests.
The implementation remains in the package; former stage-level functions
remain callable internally but are no longer exported.

The package previously exported 38 `massive_*` functions. This candidate
exports 15 file-backed descriptors, bounded readers, PCA projection, graph
construction, and graph import helpers. It internalizes 23 optimizer,
clustering, search, and diagnostic stages. `cluster_landmarks()` is also
internal; the public landmark route is `graph_cluster(..., landmarks = ...)`.

The current resident one-case benchmark worker does not call any of the
newly internal functions. Its explicit package calls use retained public
helpers. A wider scan found 42 older benchmark R scripts that do call
stage functions; see `legacy-stage-callers.csv`. These are stage-level
experiments and source-locked historical runs. They were not rewritten or
silently switched to a new algorithm. Rerunning one against a new package
requires a separately versioned migration to the four public analysis
calls, or an explicit internal-stage research harness. Its original image
and result identity remain the reproducible historical reference.

The former 850-line package vignette is preserved beside this audit. The
replacement package vignette describes the four analysis calls and the
minimum graph-preparation helpers required for full file-backed fits.
It makes no claim that a raw matrix can automatically build a full graph.

Verification: R 4.6 package source installation on Silvano's Mac passed;
focused public API, storage-routing, and unified-clustering tests passed;
new vignette knitted to Markdown; source-style and diff checks passed.
The pkgdown configuration check passed on a temporary Linux copy with its
R-version requirement relaxed for that documentation check only. A complete
Mac vignette HTML build could not run because Pandoc is absent. No benchmark
result or GPU quality claim is changed by this API audit.
