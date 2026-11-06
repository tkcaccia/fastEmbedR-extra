# Mac resident CPU and Metal panel from fastEmbedR main

Package commit: `afeaffc39a607c00db5899c284451c6cdbf741bb`.
The checked Mac installation is under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-release-v5-20261106`.
The source-locked runner and results are under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-afeaffc-benchmark-20261106`.
The input dimensions and digests are in `dataset-inventory.json`.

The resident full-data panel covers all 11 comparison datasets, PCA,
2D/3D t-SNE and UMAP, Leiden and Louvain, seeds 4/17/42, and one-core CPU,
four-core CPU, and one Metal GPU: 693 cases. Two COIL20 CPU/Metal UMAP
cases completed as source-locked admission pilots. The remaining 691 cases
were launched in a serial queue (PID 46249 at launch). A case runs in a
bounded child process, records quality, peak resident memory, swap, package
and input checksums, and output cleanup. The queue stops on an uncertain
cleanup, timeout, more than 1 GiB new swap, less than 100 GiB free disk, or
three consecutive scientific failures. `cases.jsonl` contains the exact
staged case JSON and queue plan.

This is the resident fastEmbedR panel. File-backed, landmark, competitor,
Deep1B stress, and additional CPU core-count lanes still require separate
controlled runs. The old stopped panel results remain preserved.

The HPC worker uses different preprocessing and t-SNE settings; these
source-locked results are not direct cross-platform comparisons. See
`benchmarks/shared/cohort-policy-20261106.md`.

## Queue stop and versioned continuation

The original queue stopped at one-based index 458, the 965,282-row mass41
single-core 3D t-SNE case. It reached the 1,800-second limit; its failed
result and original queue log remain intact. The other 457 queue cases
before it completed. A read-only process check found no remaining R worker
or original process group, 379 GiB free disk, and 7.69 MiB system swap.

`resume_panel_v1.py` is a separate controller for indices 459–691. It
verifies the original queue and worker hashes, original stop point, failed
case, no later outputs, old PID absence, disk and swap before running. It
uses the original case manifests and runner. It records a separate status
log and leaves the old results untouched. One-core 3D t-SNE cases with at
least 965,282 rows are explicitly recorded as **deferred** because the
first such case exceeded the existing limit. They require a separately
budgeted experiment; they are not successes or omissions from the matrix.
The continuation retains the original stop conditions for timeout,
cleanup, disk, swap and three consecutive failures.

The versioned controller was installed under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-afeaffc-resume-v1-20261106`.
Its SHA-256 is
`f3460d81c2c5c88e90e3566d32da07ecf73dee81c1747f555e734cf41782728f`.
The Mac preflight accepted the 691-case original queue and identified 11
future deferred cases. It started at 2026-11-06 13:30:46 UTC as PID 58711;
the first active case is index 459, mass41 four-core 3D t-SNE. Its status
was recorded in the separate `resume-status.jsonl`; no final result was
claimed during that continuation.

Continuation v1 stopped safely at index 459: the 965,282-row mass41
four-core 3D t-SNE also reached its 1,800-second limit. Its `run.json`
records code 124 and stable 7.69 MiB system swap. The R worker and both
controller process groups were absent on a later read-only check; 379 GiB
remained free. The failure result and v1 status log are preserved.
`resume_panel_v2.py` verifies both prior stop points and source hashes,
then starts at index 460. It explicitly defers the 22 remaining large
one- and four-core 3D t-SNE cases for longer, separately budgeted runs,
while retaining the bounded original runner for the other 210 cases.
Deferred cases are not counted as benchmark successes.

The v2 controller was installed under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-afeaffc-resume-v2-20261106`.
Its SHA-256 is
`eef2d27de9bd98d4082d3f4c68c2d50f379d2e72a92bbe65b902d108d31f61d2`.
Mac preflight accepted both recorded failures, original source identities,
and 22 future deferrals. PID 59214 began at 2026-11-06 14:04:12 UTC
with index 460, the mass41 Metal 3D t-SNE case. The run remains active;
its own `resume-status.jsonl` is authoritative for later results.
