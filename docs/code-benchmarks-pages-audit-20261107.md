# Code, benchmark, and GitHub Pages audit — 2026-11-07

## Scope and source identity

- Package baseline: `tkcaccia/fastEmbedR` main `535d071849945db3fa550d3c50f80633b91748cc`.
- Benchmark baseline: `tkcaccia/fastEmbedR-extra` main `57534e136cd8422c6ee9fde2ba6f6cfcbd70b1e9`.
- Narrow corrections: package `9b50054` and companion `6b2fb22` on main.
- The active source-locked benchmark jobs were not changed or restarted.

This is a targeted review of the public API, current resident benchmark
workers, HPC launch guards, CI results, and live Pages. It is not a formal
verification of every native kernel.

## Findings, in priority order

1. **macOS hardware CI is red.** The baseline R CMD check passed on Ubuntu
   release and devel but failed on macOS arm64 with 22 Metal tests reporting
   `failed to build Metal pipeline: Compilation failed`. The log does not show
   the compiler's underlying diagnostic. Capture that diagnostic and fix or
   qualify the shader on the runner before claiming cross-platform release
   validation. Do not suppress the device tests to make CI green.
2. **The accepted one-call file-backed API is not on main.** Current full
   file-backed `umap()` and `tsne()` require a prepared graph. The public
   `graph_cluster()` signature still accepts landmark and graph controls in
   `...`. A uniform fit summary with backend/devices, scope, stage timings,
   memory and bounded output reads is incomplete. The four-entry candidate
   exists in an isolated checkout and needs device and regression qualification
   before integration. Pages accurately reflects current main, so it should
   change together with the implementation.
3. **An archived HPC worker accepted direct submission.** Its parent
   `submit.sh` rejected the old mixed resident/file-backed campaign, but
   `massive-data/real-data/case.sbatch` could be submitted independently and
   run a legacy CUDA route without the qualified lifecycle wrapper. Commit
   `6b2fb22` rejects it at entry; a test now verifies exit 78 before any
   scheduler call. No HPC file-backed or streaming science was run in this
   audit.
4. **Baseline Windows CI was red for three POSIX-only file-backed tests.**
   The relevant implementation uses POSIX memory mapping. Commit `9b50054`
   adds Windows skips to the three tests that reached those routines. This
   does not qualify file-backed execution on Windows. Recheck CI after the
   commit.
5. **Pages had three broken provenance links.** The rendered README linked
   `inst/NOTICE`, `inst/COPYRIGHTS`, and
   `inst/THIRD_PARTY_DEPENDENCIES.json` relative to the site root, returning
   404. Commit `9b50054` points to the corresponding GitHub source files.
6. **Benchmark result interpretation needs an explicit timing contract.**
   The current matched CPU worker preserves float32 input and records loading,
   preprocessing, graph construction, fitting, quality, and writing as
   separate stages. `fit_seconds` alone excludes preprocessing and graph
   construction. Publication comparisons must state which stages are included
   and show matched end-to-end timing alongside fit time. Conversion to double
   in the shared validation script is used for competitors or quality samples;
   the fastEmbedR fit path requires float32.
7. **The benchmark repository lacked an automatic validation workflow for
   its policy and timing tests.** A lightweight `benchmark-policy` workflow
   now runs launcher rejection, float32 timing, and matched worker contract
   tests on relevant changes. Its first GitHub run must pass before relying
   on the gate. It does not qualify device behavior or scientific quality.

## Checks performed

- Package `Rscript tools/check_source_style.R`: passed.
- Package and companion `git diff --check`: passed before commits.
- Companion `benchmarks.linux.unified.test_gpu_pause` and
  `benchmarks.shared.test_fastembedr_timing_precision`: 6 tests passed.
- Matched CPU worker Python test discovery: 21 tests passed.
- Live Pages home and reference index were inspected; Pages build succeeded
  on the baseline even though the R CMD check failed.

## Release gates

Resolve macOS Metal CI, qualify and merge the four-entry API candidate,
rerun the policy/timing tests on the final benchmark revision, and regenerate
Pages from the same source commit before treating the manuscript tables as
release evidence. Keep Mac CPU/Metal and HPC resident CPU/CUDA cohorts
source-locked; never run file-backed or SSD-streaming science on UCT HPC.

## Live follow-up on 2026-11-07

- Package main `110f0f2` added a macOS 15 arm64 check beside the latest macOS
  runner. In [run 42371222345](https://github.com/tkcaccia/fastEmbedR/actions/runs/42371222345),
  the source build, Windows release check and Ubuntu release check passed.
  The macOS latest check still failed 22 Metal tests at pipeline creation for
  `signed_hash_project` on hosted macOS 26.7.2. The error reports only
  `CompilerError Code=2`, without a shader diagnostic. macOS 15 and Ubuntu
  devel had not finished at the time of this audit. This remains a release
  blocker; the passing small physical M3 Ultra device probe does not resolve
  the hosted-runner failure.
- The live Pages home, reference index and UMAP page returned HTTP 200. All
  31 distinct internal links found across those three pages also returned
  HTTP 200. The reference index puts `pca()`, `tsne()`, `umap()` and
  `graph_cluster()` in its main section, and the home page's previously broken
  provenance links now target GitHub source files. The published UMAP manual
  still requires a prepared symmetric graph and file-backed initialization
  for a full file-backed fit. It must be regenerated after the accepted
  one-call API is implemented and qualified.
- The source-locked Mac panel completed 459 cases, then stopped on the
  965,282-row mass41 3D CPU1 t-SNE case after its 7,200-second limit. A
  separate CPU4 diagnostic was still running when checked; its outcome must
  be retained before starting the guarded continuation. This is a real
  resource-limited case, not a successful benchmark measurement.
- The matched HPC resident worker enforces float32 input and separate stage
  timers. Its v3 Python test set passed 21 tests. An additional ImageNet
  8-core Louvain pilot reached scheduler `COMPLETED 0:0` and wrote source,
  input, memory and method manifests; the other FlowRepository pilot was
  still running. Treat the ImageNet numbers as provisional until the
  cohort's complete per-case audit has run. No file-backed science or
  large-image checksum was performed on the HPC head node.

## Source and benchmark follow-up on 2026-11-07

- Package `eae9c2a` adds an offline Metal shader compilation diagnostic to
  both hosted macOS checks. At inspection, run 42373063661 had built its
  canonical source package and completed the diagnostic step on macOS latest;
  the platform checks were still running. A completed diagnostic step is not
  evidence that the complete package check or Metal tests passed. Inspect its
  terminal logs before resolving the macOS failure.
- The resident Mac v2 worker verifies dataset SHA-256 and shape, but does not
  assert that loaded data or PCA preprocessing scores retain the `float32`
  class. Its result auditor also has no precision field to check. File names
  and hashes alone do not prove the data type. Keep the source-locked v2
  worker and partial results unchanged; the next versioned Mac worker and
  independent auditor should reject a precision change before comparing
  its timings with the HPC v3 cohort.
- HPC matched worker v3 explicitly rejects file-backed input and non-float32
  input or preprocessing scores. Its 21 unit tests, including manifest and
  audit rejection cases, passed locally. The Mac v3 continuation controller
  test and six launch/timing policy tests also passed. These are code checks,
  not a complete scientific audit of all running cases.
- Package `docs/backend-capabilities.md` had three stale statements: it said
  resident landmark t-SNE and UMAP reject multiple CUDA devices, two-GPU
  resident t-SNE was untested, and Metal landmark PCA projection lacked a
  device check. Source and recorded device evidence support narrower current
  descriptions: small two-A10G 2D/3D t-SNE execution and a 100-row Metal PCA
  projection check passed; partial-landmark UMAP accepts coordinated devices
  in source but still lacks device and real-data quality qualification.
- The live Pages home, reference index, PCA, t-SNE, UMAP, clustering, and
  massive-data vignette returned HTTP 200 during this review. Its UMAP page
  still describes a prepared graph and initialization for a full file-backed
  fit. That matches current main, but does not meet the accepted one-call API.
  The accepted API candidate remains isolated and requires device/recovery
  qualification before Pages can truthfully present it.
- An expanded read-only Pages crawl checked 78 pages and assets, following
  2,003 internal links, with no HTTP failures. This verifies reachable links,
  not that every example or scientific statement is correct.
- One-L40S resident pilot 1607281 failed before calculation. Its copied
  two-GPU launcher check required two distinct device IDs despite asking for
  exactly one GPU. The 28-second Slurm failure, empty result directory, small
  source-locked scripts, and logs are preserved under
  `benchmarks/linux/resident-gpu-535d071-20261107-failed-pilot`. A corrected
  versioned runner and six allocation tests are staged separately. Neither
  pilot provides a CUDA result or qualifies shutdown after a GPU child.
  Related two-L40S pilot 1607250 was still queued when checked. An attempted
  hold was rejected by automatic approval review because changing an active
  scheduler job conflicts with the project instruction to leave such jobs
  untouched. No hold, replacement submission, or in-place script edit occurred.
- [R CMD check run 42373063661](https://github.com/tkcaccia/fastEmbedR/actions/runs/42373063661)
  is terminal: Windows and both Ubuntu lanes passed, while macOS 15 and
  macOS latest failed at runtime Metal pipeline creation. Both hosted Macs
  found a Metal command-line compiler and compiled the extracted native KNN
  shader offline. The runtime failures affect independent KNN and 3D t-SNE
  pipelines, so this diagnostic does not support a simple missing-compiler
  explanation. The underlying runtime error is still only
  `CompilerError Code=2`; root cause and a release-safe fix remain open.
- The corrected one-GPU v2 files were staged in a new HPC scratch directory
  without submitting a job, changing the old pilot, or hashing the image on
  the login node. The six local allocation tests passed; actual device and
  cleanup qualification remains pending.
