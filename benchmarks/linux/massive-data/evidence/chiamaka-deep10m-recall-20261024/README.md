# Deep recall recheck, 24 October 2026

This is an off-cluster qualification record, not a replacement for the
historical two-L40S results. UCT HPC GPU work remains paused pending the
user's explicit release and administrator approval. No UCT GPU job was
submitted for this recheck.

## Inputs and runtime

- Deep base rows 1,000,001 through 11,000,000, 96 float32 columns.
  The headerless 3,840,000,000-byte slice was read from the UCT BigANN
  source without modifying it, and the Chiamaka copy matched its SHA-256:
  `e12fac972ad7931a11402a0cdc64a15d2fc0aeed8a4a4e28fea38c31a9e35826`.
- The Chiamaka candidate SIF had SHA-256
  `5efed6df4b9885a492ef7abb5921b72e7c3547ffe8d632fb8650c18885cf9e28`.
  Its isolated fastEmbedR 0.1 installation used faissR 0.1. The CUDA IVF
  source file matched local SHA-256
  `ad3aeed9b7388ecbc6313dddcdf93578bc20ada1174293cd815ecc2e662939c0`.
- One RTX 5060 Ti was used. The 10M full-graph case requested k=30,
  10,000 query rows per batch, 200,000 reference rows per shard, 8 GB
  memory budget, and 128 exact-audit rows. An eight-hour process limit
  was imposed. This test had no checkpoint.

## Result

The 10M graph reached **reference shard 28 of 50** and then failed in
`cuvsStreamSync(persistent query)` with `cudaErrorLaunchTimeout`. The
Chiamaka kernel log at **2026-10-24 11:58:05 local time** reported
`NVRM: krcWatchdog_IMPL: RC watchdog: GPU is probably locked` and
`NVRM: Xid ...: 8, pid=2954355, name=R`. The process exited nonzero
before the recall audit. Its incomplete graph files were removed by the
non-checkpointed package route. The prior 10M recall warning is therefore
**unresolved**; this run supplies no 10M recall or performance claim.

Two bounded checks after exit found the owned timeout, Singularity, and R
PIDs absent; `nvidia-smi` reported no compute process and 0% GPU
utilization. That is cleanup evidence, **not** a driver-health clearance.
No further Chiamaka GPU case was launched after this Xid.

The 1M slice from the same source range was checked separately: its
original 128-row exact audit and a second, newly seeded 128-row holdout
both had mean and minimum neighbor-ID recall of 1.0. The four rows that
failed the historical 1M two-GPU audit also had recall of 1.0 in this
single-GPU run. These observations do not certify 10M or two-GPU recall.

## Follow-up gate

Investigate the long cuVS query kernel on a display-attached GPU before
another device run. A smaller bounded query unit and checkpointed graph
run need separate validation; do not automatically retry after a timeout
or Xid. A genuine two-GPU holdout rerun remains necessary to clear the
historical publication warning, and cannot run on UCT while its GPU pause
is in force.
