# Resident partial-landmark CUDA UMAP candidate

The isolated package candidate now forwards two to four CUDA devices to
the coordinated resident reference fit, materializes the query KNN in RAM,
and distributes fixed-reference query projection across those GPUs. The
sharded refinement samples negative examples from reference rows only;
this is explicitly recorded in result metadata. The CUDA route is staged,
not device-qualified or publication-ready.

## Checks completed

- Source style and `git diff --check` passed on 4 November.
- A CPU-only R 4.5.3 package build passed in `/tmp`; its copied
  `DESCRIPTION` required R 4.5 only for this local check. The source
  package continues to require R 4.6.0.
- Focused mocked routing, sharding, and no-fallback checks passed
  (17 expectations), as did the existing landmark regression file.
- `candidate.patch.xz` is the complete isolated candidate patch against
  base commit `4571fe483e29a528b4b837b5c9f5cefe509fac7b`.
  Its SHA256 is
  `dbc6da4a9e7c9d094db287165a9d00bf40cb425b49b5bf42bbc94bc1258c810e`.

## Still required

Build with CUDA, verify actual two-GPU execution and cleanup, compare
single- and multi-GPU quality on real datasets, inspect memory, and
resolve the current landmark/full UMAP quality gap before benchmarking.
A further two-A10G Hugging Face submission was rejected by automatic
approval review because the existing US$2 cap had insufficient proven
headroom. No new paid job was created. UCT L40S testing remains subject to
the reviewed-source, immutable-image, and lifecycle pilot gates. Scientific
work on UCT must stay resident in RAM.
