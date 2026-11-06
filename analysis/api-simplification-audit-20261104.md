# Public API and benchmark audit, 2026-11-04

This audit covers the isolated fastEmbedR package candidate and companion
benchmark candidate. It does not change a released package or historical
source-locked benchmark outputs.

## Unified clustering update

`graph_cluster()` now accepts an in-memory matrix, a resident KNN graph,
a file-backed `massive_matrix()` descriptor, or a certified file-backed
full graph. A matrix selects the existing automatic resident route;
a file-backed graph selects full-graph mode. Storage-specific controls
are passed through `...` only for matrix/file-backed inputs; a resident
graph rejects them explicitly. The file-backed full-graph route omits
inapplicable `n_runs` and `steps` arguments. The default multi-CPU
full-graph request selects fit mode; an explicit incompatible request
still fails.

A checksum-verified isolated Mac R 4.6 build passed a focused package
test for all four input types and resident-graph control rejection. The
final source archive under Stefano is
`fastEmbedR-api-unified-v4-20261104/source.tar.xz`, SHA-256
`18902d45dd0a6d0278f52d3712e8892a38d6ec16516644fc9ee2114f5be92973`.
The package style check and diff check pass. The README, usage guide,
file-backed vignette and pkgdown start section now lead with this one
clustering entry point. The two current general benchmark scripts that
used `massive_cluster()` were migrated and all 305 benchmark R files parse.
Historical source-locked scripts were preserved.

The exported low-level `massive_*` stage functions remain for compatibility
and specialized benchmark workflows. The site index now shows only the main
analysis and input functions. Forty-two advanced stage topics carry the
`internal` documentation keyword, so pkgdown hides them from its reference
index while `fastEmbedR::` calls continue to work. `pkgdown::check_pkgdown()`
passes with no missing topics. Removing these functions from the namespace
is a later compatibility change requiring migration of current stage-level
callers; this update does not claim that gate.

The revised file-backed vignette's R examples ran against the versioned Mac
R 4.6 candidate in Stefano. The Mac has no Pandoc executable, so its knitted
Markdown was copied locally and converted to HTML with Pandoc. Both steps
passed. The package source-style and candidate diff checks passed after the
site-index change. No site was published.

## Public surface

The package previously exported 59 functions. It now exports 55. One
`massive_read_rows()` call reads bounded rows from file-backed matrices,
full-graph Leiden/Louvain/Walktrap results, or landmark-clustering results.
The four result-specific readers remain implemented internally. Their
return values and range checks are retained, but their exported names are
retired. Calls using `fastEmbedR::massive_read_cluster_rows()` or the other
three retired names must migrate to `fastEmbedR::massive_read_rows()`.

The ordinary workflow uses `pca()`, `tsne()`, `umap()`,
`precompute_knn()`, `graph_cluster()`, `massive_matrix()`,
`massive_read_rows()`, and `evaluate_embedding()`. KNN objects can be
passed directly to `umap()` or `tsne()`. `cluster_landmarks()` and
`massive_cluster()` remain exported for compatibility and specialized
workflows; they are absent from the main reference index.

## Input-driven storage routing, 2026-11-05

The same `pca()`, `tsne()`, and `umap()` entry points now infer a storage route
from a file-backed descriptor when `massive` is omitted. PCA uses its
memory-aware auto route. A prepared file-backed graph selects full-graph
t-SNE or UMAP; a file-backed matrix requires explicit `landmarks` before
landmark embedding is selected. An explicit `massive` value still controls
the route and no approximation is selected without a landmark request.

An isolated Mac R 4.6 build under Stefano passed the focused storage-routing
and full-graph package tests with the package-aware test harness. CUDA-only
tests were skipped because the Mac has no NVIDIA GPU. Source style,
`git diff --check`, and `pkgdown::check_pkgdown()` passed after integration.
The tested Mac build and logs are under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-auto-route-20261105`.
The source archive SHA-256 is
`e28235348bcdc8f0d268ad8ff251acf16ad615824706abad79285d3b756c19e8`;
the two test files were corrected in that source tree before the final passing
run. No benchmark performance claim follows from these small API tests.

## Resident landmark clustering through graph_cluster, 2026-11-05

`graph_cluster(matrix, landmarks = ...)` now delegates to the existing
resident `cluster_landmarks()` implementation. It returns the same all-row
labels and reference metadata, and rejects incompatible file-backed or
resident-graph controls. Default Leiden and explicit Louvain routes passed
focused Mac R 4.6 tests alongside ordinary graph regression. One older
graph-options test expected a prior error message; the same failure was
reproduced on the unchanged baseline, then its expectation was updated.
The Mac evidence is under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-cluster-unified-20261105`.

The README, usage guide, and getting-started vignette now present
`graph_cluster()` for full and landmark clustering. `cluster_landmarks()`
remains exported, marked internal in its help topic, and omitted from the
pkgdown reference index. The staged resident benchmark worker calls
`graph_cluster()` for landmark cases; historical and source-locked probes
were preserved. Package style, `pkgdown::check_pkgdown()`, both focused Mac
test files, benchmark worker parse, and candidate diff checks passed. This
is a compatibility-preserving surface simplification; the exported symbol
count has not decreased at this step.

## Documentation

- The package README, usage guide, getting-started vignette, experimental
  file-backed vignette, package help topic, and pkgdown reference index now
  lead with integrated calls and identify direct stages as advanced.
- All 55 exports have a corresponding Rd alias; all 65 Rd topics parse.
- The reference manual built as a 72-page PDF from the isolated package
  copy. The build reported LaTeX line overflow warnings in some long
  parameter descriptions, but completed without an Rd parse error.
- `_pkgdown.yml` parses, lists all 55 exports once, and has no duplicate
  reference entries. Relative Markdown destinations in 19 package README,
  guide, and vignette files resolve locally.
- Both vignettes rendered successfully from the isolated CPU package build.
- A complete pkgdown site built successfully in an isolated temporary
  directory after fetching its standard web assets. The current pkgdown
  version failed while converting optional `llms.txt` documentation, so
  `_pkgdown.yml` disables only that optional output. Home, reference,
  both articles, news, sitemap, redirects, search index, and pkgdown's
  final problem check completed. No site files were published.

## Benchmark code

All 305 R files under `benchmarks/` parse. The nine calls to retired
result-specific readers in the current candidate were migrated to
`massive_read_rows()`. The active reviewer-validation controller's six
calls to removed `landmark_tsne()` and `landmark_umap()` wrappers were
migrated to `tsne()` and `umap()` with explicit landmark arguments. A CPU
Iris test exercised the migrated landmark argument shapes.

A static audit of the 145 current R benchmark scripts found no
`fastEmbedR::` symbol absent from the new export list. This excludes
`legacy/` and versioned `panel-v*-stage/` copies. The historical copies
still call APIs from their source-locked package versions and must stay
paired with those versions; they are not launchers for the current
candidate. Static symbol matching does not establish scientific quality
or make those historical scripts compatible with a future release.

Focused CPU tests passed for the unified reader, Louvain, Leiden, and
Walktrap. Small integrated `tsne()` and `umap()` landmark calls using the
reviewer controller's argument shape returned all rows. The package
source-style check and both candidate `git diff --check` checks passed.

## Release gate

The site, reference index, Rd files, vignettes, source style, and focused
API tests passed locally. This is not a full package release check;
GPU-specific calls, package-wide checks, and publication benchmark
validation remain separate gates.
