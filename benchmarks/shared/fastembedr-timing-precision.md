# Precision audit for fastEmbedR timing inputs

Audit date: 2026-11-07. This audit concerns the matrix passed to a timed
fastEmbedR fit. Double precision remains appropriate for some competitors and
for bounded, untimed exact-neighbor or quality calculations. Their values must
not be reported as fastEmbedR fit time.

| Benchmark path | Timed fastEmbedR input | Disposition |
|---|---|---|
| Mac main-535d071 v2 resident panel | Source `float32` object; no double conversion in the worker | Running source-locked panel; preserve it. A future panel should also record the observed input class in each result. |
| HPC matched-main-535d071 v3 resident CPU | Source `float32` object; rejects non-`float32` input or PCA preprocessing output | COIL20 42/42 independently audited; Fashion-MNIST v3 in progress. |
| HPC matched-main-535d071 v1/v2 | Converts the source object with `float::dbl()` before fit | Preserve as diagnostic evidence; exclude from matched Mac/HPC timing comparisons. |
| Shared JSS reviewer runner | Builds `x_fast` as `float32` before `system.time` and passes it to every fastEmbedR full-data or landmark fit | Explicit fail-closed `float32` check added. Double conversion elsewhere supplies competitors or bounded quality/reference checks. |
| Resident one-case CPU/CUDA worker | Returns the loaded resident object to `resident_fit` without conversion | Now rejects any input that is not `float32` and records input precision. The Deep1B loader materializes `float32` before timing. |
| Older pilots and legacy copies | Mixed historical double conversions | Preserve their results under their original source versions; do not use them as the corrected cohort. |

The benchmark worker and the installed package are separate. Correcting the
worker does not require a new Singularity image while package commit `535d071`
is unchanged. Never rewrite a staged worker or image used by a queued or
running job: create a new cohort and audit its source and input identities.
