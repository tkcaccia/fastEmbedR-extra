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

## Fashion-MNIST resident UMAP quality audit

The original source-locked panel completed all 18 Fashion-MNIST UMAP cases
(70,000 rows, 784 input columns, rank-30 preprocessing, seeds 4/17/42,
two or three output dimensions, CPU1/CPU4/Metal). The paired manifests have
the same input SHA-256 (`7be6826c092c19aaaf47b97b602e74f42d2b9ba0a61ecda2de0c91cdbc6b4006`),
source SHA-256 (`c624492b26aa4da2797d44f0940a19a4fe15d77156b06d193a51b313f1fea759`),
worker SHA-256 (`e772286c53536e009471f8b8a5ae2f09db67f01e161f8aee892a46d669619da4`),
and seed and output dimension within each trio. All 18 `run.json` files
record completed exit 0, clear cleanup, and unchanged 7.69 MiB system swap;
the six Metal `metrics.json` files record `observed_backend: metal`.

| Dimensions | Seed | CPU1 trust / label accuracy | CPU4 trust / label accuracy | Metal trust / label accuracy | Metal fit seconds |
|---:|---:|---:|---:|---:|---:|
| 2 | 4 | .9752 / .7617 | .9754 / .7700 | .9752 / .7617 | 10.438 |
| 2 | 17 | .9781 / .7150 | .9781 / .7217 | .9787 / .7300 | 10.415 |
| 2 | 42 | .9770 / .6817 | .9769 / .6817 | .9772 / .6933 | 10.415 |
| 3 | 4 | .9802 / .7700 | .9797 / .7667 | .9803 / .7667 | 1.681 |
| 3 | 17 | .9808 / .7433 | .9809 / .7367 | .9809 / .7450 | 1.667 |
| 3 | 42 | .9818 / .6900 | .9819 / .6850 | .9814 / .6983 | 1.664 |

On this full-data, 70,000-row Fashion-MNIST cohort, Metal trustworthiness is
within 0.0006 of CPU1 for every paired seed and dimension. Metal label
accuracy is within 0.0150 of CPU1. This supports the **resident full-data
Fashion-MNIST one-call route** at commit `afeaffc`; it does not close the
earlier fixed-graph paired Fashion quality gate, nor qualify file-backed or
landmark Metal UMAP. The markedly different 2D and 3D Metal fit timings
reflect different execution policies in the published package source:
resident 2D Metal UMAP runs the first half of its epochs on one CPU thread
before the native Metal optimizer, whereas resident 3D uses Metal for all
epochs (`R/fast_knn_umap.R`, `optimize_prepared_umap_metal`). The panel's
`observed_backend: metal` confirms its selected nearest-neighbor and
optimizer route but does **not** mean every 2D optimizer epoch ran on the
GPU. Future benchmark workers must record the pipeline and CPU/GPU epoch
counts; do not present these timings as an all-GPU comparison. Source evidence:
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-afeaffc-benchmark-20261106/results/fashion_umap_*/{metrics,run,provenance}.json`
and the corresponding `manifests/fashion_umap_*.json` on Silvano's Mac.

At the same read-only audit, 42 complete Metal/CPU1 UMAP pairs were present
across seven datasets and both dimensions. The worst single-seed Metal
trustworthiness difference was -0.0097 on Tabula Muris 2D, seed 17;
its Metal-minus-CPU1 label-accuracy difference was -0.0267. Across all
three Tabula Muris seeds, mean trustworthiness differences were +0.00307
(2D) and +0.00293 (3D), so the single-seed failure should be retained and
examined rather than treated as a universal backend regression. The panel
was still in progress; this is a snapshot, not a final eleven-dataset
quality conclusion.

`worker_v2.R` and `run_case_v2.py` are a **future, versioned runner**, not
the worker for the active panel. They require Metal UMAP to report its
optimizer pipeline and CPU warm/Metal epoch counts, reject missing or
inconsistent stage metadata, and write those counts into `metrics.json`.
Both files passed local syntax checks. They must receive a separate Mac
device case and source hash before their results can enter a cohort; the
running panel's worker and results remain unchanged.

## First large Metal t-SNE continuation result

Continuation v2 completed index 460,
`mass41_tsne_metal1_d3_s4_r1_afeaffc`: 965,282 rows, 14 columns,
three output dimensions, seed 4. The fit took 1,064.108 seconds and the
bounded case took 1,071.978 seconds overall. `metrics.json` reports
`observed_backend: metal`, trustworthiness 0.9738 and label accuracy 0.8683.
`run.json` reports exit 0, peak RSS 4,001,038,336 bytes, unchanged 7.69 MiB
system swap, no timeout and clear process-group cleanup. The input, source,
DLL, runner and worker hashes match the original panel manifest. The
same-size CPU1 and CPU4 3D t-SNE seed-4 cases each exceeded the 1,800-second
case limit; they remain failed evidence, not CPU timings for a speedup
ratio. The v2 controller then deferred the remaining corresponding large
CPU1/CPU4 cases and started the Metal seed-17 case at index 463. This is
one large-case development result; quality and timing replication remain.

## Continuation-aware audit

`audit_continued_panel.py` independently combines the original queue and
versioned continuation logs. It checks queue indices, controller and queue
hashes, result and package identity, recorded shape and backend, quality,
timing, swap and cleanup. It reports completed, failed, deferred, running
and pending cases separately. The original `audit_panel.py` remains the
historical audit of an uninterrupted queue; it cannot represent the two
continuations correctly. The new audit's fixture suite passed 10 tests,
including a deferred case and a tampered controller hash.

A read-only audit snapshot at 2026-11-06 14:32 UTC reported 460 completed,
two failed 1,800-second CPU cases, two explicitly deferred CPU cases, one
running Metal case, and 228 pending cases out of 693 planned, with no
provenance or result-audit problems. PID 59214 was independently observed
live; a log entry alone is not proof that a worker is still running.
The snapshot is preserved under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-main-afeaffc-audit-v2-20261106/snapshot-20261106-1432.json`.
The audit script SHA-256 is
`5f9a2c94bc415baab37a00b3b30d14b75296dd08770df082777b20f12550ec7f`.
