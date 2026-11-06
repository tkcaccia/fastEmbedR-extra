# File-backed clustering first-pass scheduling, 5 November 2026

This is an isolated Mac performance experiment under
`/Users/silvanopiazza/Documents/Stefano/fastembedr-louvain-firstpass-20261105`.
It reused the existing 100,000-vertex/30-neighbor and
50,000-vertex/200-neighbor file-backed fuzzy graphs without duplicating
large graph files. No file-backed scientific calculation ran on HPC.
The candidate executes the first Louvain local-move pass serially, when
most neighbors change and parallel row proposals quickly become stale;
later passes still use the requested CPU workers. Leiden uses this Louvain
phase before its refinement. The source archive SHA-256 is
`9617ca2b2653ff598563aedfa77588cfea11afa89ffddeaaf2c44de6f9bb9854`.

Two independent paired runs gave the following elapsed seconds. Each pair
used the same seed, input, pass count and memory budget.

| Method / graph | Cores | Baseline run 1 | Candidate run 1 | Baseline run 2 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Louvain 100k x 30 | 1 | 0.339 | 0.340 | 0.343 | 0.340 |
| Louvain 100k x 30 | 4 | 0.534 | 0.428 | 0.535 | 0.427 |
| Louvain 50k x 200 | 1 | 0.705 | 0.709 | 0.708 | 0.696 |
| Louvain 50k x 200 | 4 | 1.053 | 0.773 | 1.053 | 0.773 |

A paired 100k x 30 Leiden check took 0.696 seconds (one core) and 0.958
seconds (four cores) in the baseline, versus 0.698 and 0.845 in the
candidate. In all comparisons, label SHA-256 values, community counts,
modularity and move counts matched exactly. The installed candidate passed
focused `test-massive-louvain.R` and `test-massive-leiden.R` on Mac R 4.6.

The four-core route improved consistently, by roughly 20% and 27% for
Louvain and 12% for Leiden in these small fixtures. It **still trails the
one-core route**, so this is an overhead reduction, not a multi-CPU
speedup or publication-scale scaling result. The change is integrated into
the isolated package candidate; the next work is a new parallel update
strategy or workload calibration for larger graphs, with quality and
memory checks.
