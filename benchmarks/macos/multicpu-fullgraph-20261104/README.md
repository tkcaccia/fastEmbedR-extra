# File-backed full-graph multi-CPU clustering qualification

Status: implemented in the isolated package candidate, not merged or
released. The v2 source archive used for the Mac build has SHA256
`24b3032ff0a584928655365d6aba30332a033c3c669bf220ec034557908f7d2f`.
The checksum-verified Mac log bundle has SHA256
`f46194f96b9b2f1b85854df6d439e5f13bd1b1ed2d65a70a89a11a1d3781578b`.

The CPU route prepares bounded row candidates in parallel, validates
neighbor labels after earlier moves, and commits Louvain and Leiden moves
in a stable order. Louvain candidate ties are sorted by community ID.
The public `massive_louvain()`, `massive_louvain_level()`,
`massive_leiden()`, and `massive_leiden_refine_level()` accept `n.cores`.
The `massive_cluster()` full-graph facade requires
`parallel.mode = "fit"` with multiple cores. GPU routes still use one CPU
coordinator. Results record requested and effective CPU workers and the
parallel stage.

The isolated package installed on Silvano's Mac with R 4.6.1. Focused
Louvain/Leiden and clustering-routing test files passed. A 512-row graph
had identical one-core and four-core Louvain labels, modularity, and move
counts; Leiden refinement also matched. A 100,000-row, 30-neighbor
synthetic ring had identical Louvain labels, 5,363 communities, modularity
0.7635948, and 134,126 moves at 1, 2, 4, and 8 cores.
The final high-level Leiden `parallel.mode = "fit"` test passed after
the source archive was built; its log is `test-highlevel-leiden.log`.

| CPU cores | 100,000-row Louvain elapsed seconds |
| ---: | ---: |
| 1 | 0.342 |
| 2 | 0.546 |
| 4 | 0.534 |
| 8 | 0.563 |

This parallel preparation is **slower** on the synthetic cached graph.
These timings are development evidence, not a speedup claim or manuscript
benchmark. The ordered commit phase remains serial. A larger real-data
performance panel is needed before recommending this mode for speed.
No file-backed scientific work ran on the HPC. The generated synthetic
graph and superseded Mac build copy were removed after retaining scripts
and logs under Stefano.
