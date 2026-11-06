# Mac file-backed clustering performance follow-up, 4 November 2026

These are development timings from Silvano's Mac under
`/Users/silvanopiazza/Documents/Stefano`. No HPC file-backed scientific
calculation was run. Graphs and outputs remain in Stefano; only small logs
were copied into this companion evidence directory.

The first isolated source archive changed both Louvain and Leiden's
bounded parallel-preparation scratch cap from 65,536 to 262,144 edges.
Archive SHA-256:
`a6fcfdb35c3abe31a7a165df0434bb312c415d05a5fc8037dd9fb54a2866d497`.
Its 100,000-vertex, 30-neighbor fixture generated 6 million directed fuzzy
edges and ran four Louvain passes. All partitions matched exactly.

| CPU cores | Baseline seconds | Larger-batch seconds |
| ---: | ---: | ---: |
| 1 | 0.342 | 0.345 |
| 2 | 0.546 | 0.574 |
| 4 | 0.534 | 0.550 |
| 8 | 0.563 | 0.567 |

The larger batch **did not improve performance** and was not integrated.
Its Mac log is `batch262k-100k.log`.

The existing multi-CPU package candidate was also tested on a higher-degree
50,000-vertex, 200-neighbor fixture, yielding 20 million directed fuzzy
edges. Two Louvain passes produced identical labels, 2,356 communities,
modularity 0.6894184, and 54,764 moves at one and four cores.

| CPU cores | Elapsed seconds |
| ---: | ---: |
| 1 | 0.687 |
| 4 | 1.030 |

The successful versioned log is `highdegree-50k-k200.log`. Earlier staged
scripts stopped after graph construction because one reader came from a
newer API and a generic CSR reopen lacked the saved fuzzy-graph
certification. Their failed logs remain on the Mac. The final script used
the package's manifest-verified `massive_fuzzy_graph()` reopen and the
reader matching its installed source.

The present algorithm prepares row candidates in parallel but commits moves
in order; it rechecks candidate labels after preceding moves. In both tested
degree regimes, preparation overhead outweighs its benefit. This evidence
does not justify a multi-CPU speedup claim. The next design must reduce
worker-start and stale-candidate costs or introduce a separately qualified
parallel update rule with paired modularity, connectivity, partition-quality,
memory, and scaling tests. No claimed optimization was merged from these
negative tests.
