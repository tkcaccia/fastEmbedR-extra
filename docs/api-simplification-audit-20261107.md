# Public API simplification audit (7 November 2026)

This audit compares package `main` at `535d071` with isolated candidate
`e327876`. The candidate is not a release: its installed API and resident KNN
check passed HPC compute job `1607055`, and pure R storage dispatch checks
passed locally, but its file-backed KNN and clustering preflight still await
an actual Mac package test. No file-backed scientific test was run on UCT HPC.

The intended four-function R interface must be backed by one reusable native
engine. The present Rcpp `.Call` registrations are not a supported API for
other R packages or a future R-free Python wrapper. The required C++ core,
versioned C ABI, installed R callable header, and cross-language verification
are specified in [the native-core plan](native-core-api-plan-20261107.md).

## Findings

| Limitation | Evidence | Proposed public behavior |
| --- | --- | --- |
| Too many visible entry points | `NAMESPACE` exports 31 functions, including 15 `massive_*` functions; pkgdown hides most of the latter, but `package::` still exposes them. | Keep `pca()`, `tsne()`, `umap()`, and one clustering function as the main analyses. Keep one input descriptor, one KNN preparation function, one bounded result reader, and model projection where necessary. Retain advanced exports temporarily with clear compatibility documentation; deprecate only after callers and saved results are audited. |
| Long flat argument lists | Candidate `pca()` has 18 formals, `tsne()` 43, `umap()` 32, and `graph_cluster()` 17. | Keep common scientific controls explicit. Group less common optimizer, checkpoint, and graph preparation settings into typed, validated control objects. Print resolved defaults in results so benchmarks remain reproducible. |
| Storage controls overlap | The same calls expose `storage`, `massive`, and sometimes `layout_storage` or `gpu_storage`; some values describe input location, others algorithm or optimizer state. Candidate `e327876` adds early conflict checks and prevents explicitly file-backed clustering from choosing an in-memory auto route. | Define one shared `storage = "auto"/"resident"/"file_backed"` contract and a separate, documented fit-scope choice (`full` versus landmarks). Translate legacy `massive` internally and reject conflicting settings before work begins. Preserve generic `options(storage = ..., memory_limit = ...)` as session defaults with explicit arguments taking precedence. |
| File-backed full embeddings require manual graph stages | `docs/usage-api.md` says full file-backed UMAP/t-SNE need a prepared fuzzy/affinity graph and initialization; `vignettes/massive-data.Rmd` calls `massive_umap_fuzzy_graph()` and `massive_tsne_affinities()`. | Make `umap(file_matrix, output = ...)` and `tsne(file_matrix, output = ...)` plan and run KNN, weights, initialization, and optimization in one validated call. Continue to accept prepared graphs for reuse and scientific control. Return stage timings and intermediate descriptors in the result. |
| File-backed landmark PCA is not one call | `docs/usage-api.md` explicitly says `pca()` cannot use `landmarks` with a file-backed source. | Support `pca(file_matrix, landmarks = ..., output = ...)` with all-row scores and a recorded reference fit, or clearly mark it unsupported in the capability table until implemented. |
| Clustering input name misleads | `graph_cluster(graph, ...)` accepts a raw matrix and file-backed matrix as well as a prepared graph; the resident landmark route is passed through `...`. | Keep one clustering entry point but make the input name and documentation cover data or graph. Give `landmarks`, `k`, and `vote_k` explicit validated controls instead of relying on `...`; preserve named `graph=` calls through a compatibility wrapper if renamed. |
| Results need a common interface | Resident KNN returns `fastEmbedR_knn`, while file-backed KNN returns `fastEmbedR_massive_graph`; backed full fits require `massive_read_rows()`. | Keep storage-specific payloads, but give all fits a common `summary()`, stage timing, backend/device identity, fit scope, approximation, and bounded row-read contract. Do not materialize large results implicitly. |
| Benchmark callers can bypass the intended API | Companion benchmark source still contains many `massive_*` calls, including the Deep1B worker and diagnostic scripts. | Migrate active benchmark cases to the high-level calls once equivalent stages are implemented; retain archived diagnostic scripts with their source identity. Audit each active caller before changing a source-locked cohort. |

## Order of work and acceptance checks

1. Qualify the generic `storage` and `memory_limit` candidate on the Mac,
   including actual file-backed KNN correctness, memory use, and backend
   identity. Do not merge solely on the HPC compile check.
2. Add a single validated route resolver for input, storage, fit scope,
   backend, and output. Test precedence, incompatible combinations, and
   errors before allocation or file creation.
3. Implement one-call file-backed full embeddings and landmark PCA. Run
   device-specific quality, memory, recovery, and all-row checks on permitted
   machines. Keep file-backed work off UCT HPC.
4. Introduce compact control objects without changing scientific defaults;
   test equivalence against current explicit calls and keep legacy arguments
   during a documented deprecation period.
5. Migrate active benchmarks, rebuild Rd/vignettes/pkgdown from one frozen
   package version, and verify examples plus old saved-object readers.

For each public example, record whether it is **verified**, **failing**,
**limited by measured resources**, or **not implemented** in the capability
table. Passing a synthetic route or package build does not prove quality on a
real dataset or an actual accelerator.
