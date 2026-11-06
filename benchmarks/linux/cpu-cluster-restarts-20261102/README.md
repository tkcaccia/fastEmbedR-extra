# Parallel CPU Louvain and Leiden restarts

Candidate: `in-progress/cuda-graph-options-20261102`, based on fastEmbedR
`4571fe483e29a528b4b837b5c9f5cefe509fac7b`. The exact tested source
archive is in `evidence/` with SHA256
`cd3d301b27828b400c8e5188e775587aa56afdcb36bd0bea60e6c4b3a4434b59`.
The original package checkout and source-locked Mac panel were untouched.

The candidate adds `n.cores` to resident `graph_cluster()` for CPU Louvain and
Leiden with scalar controls and `n_runs >= n.cores`. Independent seeded runs
execute concurrently. Result selection follows serial run order and picks the
highest modularity. Other backends, Walktrap, and vector consensus reject a
multiworker request. The result records `effective_cpu_workers` and
`parameters$n.cores`. A single partition still runs on one worker. This does
not make the SSD-backed full-graph coordinator parallel.

Validation used Chiamaka's existing 29 October Singularity image with R 4.6.1
and faissR's C API. The package was installed CPU-only in a temporary library.
The graph-option test file passed with no failures; two CUDA tests skipped
because CUDA was disabled. A fractional `n.cores` test exposed and led to a
fix in the existing positive-integer validator. Source style and diff checks
passed. The host's default R/faissR installation is older and lacks the
required C API; all successful validation used the container runtime.
A follow-up archive with SHA256
`de3bd85bc08744381e3fc5a2bc63415d61ce937dd3a6934c4288bfce33d1b643`
moved `n.cores` to the end of the public argument list. Its focused R 4.6.1
tests passed, including an old-style positional call. The MNIST70k timings
below used the earlier exact source archive preserved in `evidence/`.

## MNIST70k pilot

The trial reused the existing 70,000-row, 15-neighbor MNIST KNN cache on
Chiamaka. Input SHA256:
`0651d481a290cb41de4888b5288aab008ac91d971066a372f5fd1e5584e61e1a`.
Graph construction produced 249,804 mutual SNN edges. Each fit used eight
restarts, five local-move passes, resolution 1, and seed 17. The timed scope
was `graph_cluster()` only; graph construction and input loading were excluded.
Worker orders were 1, 2, 4, 8 and then 8, 4, 2, 1. All 16 fits returned
exactly identical labels within each method and the same modularity.

| Method | 1 worker (s) | 2 (s) | 4 (s) | 8 (s) | 1-to-8 ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| Leiden | 4.288 | 2.162 | 1.194 | 0.761 | 5.63 |
| Louvain | 1.265 | 0.610 | 0.365 | 0.241 | 5.25 |

Times are means of two runs. User CPU time exceeded wall time in the
multiworker cases, confirming parallel CPU work. The full per-run data,
selected labels, script, source archive, and checksums are in `evidence/`.
This is a pilot on one graph; it establishes restart throughput, not speedup
of a single Louvain/Leiden optimization or manuscript-wide performance.
