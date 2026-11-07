# Native core and cross-language API plan (7 November 2026)

## User requirement

The public R calls `pca()`, `tsne()`, `umap()`, and `graph_cluster()` must be
thin adapters over one reusable C++ algorithm core. Another R package must
be able to call supported native operations without reaching into
fastEmbedR's private `.Call` registrations. A future Python wrapper must
use the same algorithms without loading R or copying the implementations.

This is an architectural requirement, not an assertion that today's package
already provides a stable native API.

## First isolated implementation slice

An unpublished candidate at `/tmp/fer-native-core-20261107` extracts CPU
exact KNN into a standalone C++ source with a versioned C ABI. The existing
R exact-KNN adapter calls that source; an installed header and R C-callable
interface allow a separately compiled R package to call the same operation.
Standalone C++ and Python `ctypes` calls passed without R linked. R 4.6
package and downstream fixture builds passed on a UCT compute node. A
versioned diagnostic job `1607192` confirmed identical direct and external
R-package outputs and zero numerical distance difference from the public
float32 KNN result. This qualifies only the first exact-CPU-KNN slice; it
does not qualify the other algorithms, file-backed routes, or GPUs.

## Current state and gap

The observations below describe package `main` at `535d071`; the isolated
candidate above has not been merged into that branch.

- The package registers generated Rcpp `.Call` entries in
  `src/RcppExports.cpp` and disables dynamic symbol lookup. It does not
  register a documented `R_RegisterCCallable` interface.
- `inst/include` contains no installed fastEmbedR native API header.
- In the reviewed source, 32 of 46 C++/header files refer to Rcpp, `SEXP`,
  or R internals. Some math is already in plain C++ helpers, but core data
  structures, errors, interrupts, and output conversion are often bound to R.
- The existing Python script under `inst/python` is a specialized CUDA
  clustering worker; it is not a Python wrapper around all five algorithms.
- Linking Python to the package's R shared object would retain an R runtime
  dependency and would not satisfy the requirement.

## Target architecture

1. Put PCA, neighbor search, graph construction, t-SNE, UMAP, Louvain, and
   Leiden computation behind a C++17 library independent of Rcpp and Python.
   CPU, CUDA, and Metal kernels share the same validated request and result
   model; unavailable backends fail explicitly.
2. Give that library a versioned C ABI. Its inputs use fixed-width types,
   explicit array shape, strides, dtype, ownership, and device identity.
   The ABI uses opaque contexts, caller-visible status/error codes, and
   explicit resource release. No C++ exception crosses the ABI boundary.
3. Keep file-backed readers, bounded buffers, checkpoint identity, and
   recovery in the native core. The R and Python adapters provide paths or
   supported data descriptors; they do not reimplement the pipeline.
4. Make the R package a thin adapter: validate R objects, translate options,
   call the native core, and return R result objects. Install a versioned
   header under `inst/include/fastembedr/` and register an R C-callable
   function table so other R packages can use the installed native engine.
5. A future Python extension links to the same core library and translates
   NumPy arrays and file-backed descriptors. It must not import R. Document
   array layout and any required copy, including its timing and memory cost.

The stable ABI should expose capability discovery, plan/resource estimation,
fit, bounded result reads, checkpoint/resume, and cleanup. The request must
identify method, full or landmark scope, resident or file-backed storage,
backend, CPU workers or CUDA device set, seed, and method controls. Results
must report the actual backend and devices, timings by stage, peak memory,
approximation, input identity, and format version.

## Migration without two scientific implementations

| Slice | Change | Acceptance evidence |
| --- | --- | --- |
| 1. Contract | Specify C ABI types, ownership, errors, versioning, and metadata; publish an installed header. | Compile an external R package against the header; verify ABI version rejection and cleanup. |
| 2. CPU algorithms | Move one existing CPU kernel at a time behind the core, starting with exact KNN and PCA, then graph clustering, UMAP, and t-SNE. Replace its Rcpp body with an adapter in the same change. | Exact output and quality parity on fixed real-data cases; no duplicate algorithm path remains. |
| 3. Storage | Move native file-backed planning, bounded reads/writes, checkpoint and recovery under the same requests. | Bounded peak RAM, restart parity, file identity checks, and no implicit materialization on Mac or Chiamaka. |
| 4. Accelerators | Move Metal and CUDA dispatch and ownership into the core, then qualify coordinated multi-GPU routes. | Actual-device output/quality parity, GPU use, memory, error and cleanup evidence; no backend fallback. |
| 5. Other R packages | Register the stable function table with R's C-callable mechanism. | A minimal downstream package builds and runs a native operation using only the installed header and callable lookup. |
| 6. Python proof | Link a minimal Python extension to the same library and run identical fixture requests. | Same source version, result identity/tolerance, metadata and cleanup without R loaded. |

Do not claim cross-language readiness from a generated Rcpp export, a header
that only declares private functions, or a trivial Python import. Test at
least one real operation through an external R package and a Python wrapper.

## Benchmark consequences

Time input conversion separately from native fit. A row-major float32 file
can be passed through the file-backed descriptor; a column-major R matrix
or NumPy view may require a conversion or a strided native path. Record the
actual choice and bytes moved. Keep a frozen core source version and wrapper
version for each benchmark cohort. Never run file-backed scientific work on
UCT HPC.
