# Native clustering validation, 2026-07-30

## Scope

The validation compares `fastEmbedR::graph_cluster()` with `igraph` on the
identical undirected weighted graph. Timings cover clustering only; nearest-
neighbor search and graph construction are excluded. Each reported value is
the median of seeds 4, 17, and 42 after one untimed accelerator warm-up.

The package was compiled without cuGraph. Dynamic-library inspection confirmed
that the Metal build links Apple system frameworks and R, while the CUDA build
links CUDA runtime/math libraries and R. Neither binary links cuGraph,
NetworKit, or igraph.

## Hardware

- Metal: Apple M3 MacBook Pro, 8 CPU cores, 8 GB unified memory.
- CUDA: NVIDIA GeForce RTX 5060 Ti, 16 GB, compute capability 12.0, driver
  595.71.05; Intel Core i7-13700 host.

## Structured synthetic graph

The graph contains 50,000 vertices, 798,890 weighted edges, and 10 planted
communities. Every fastEmbedR backend and igraph recovered the planted
partition exactly (ARI = 1) with modularity 0.8983341.

| Machine | Method | Implementation | Backend | Median seconds | Speedup vs igraph |
|---|---|---|---|---:|---:|
| Apple M3 | Louvain | igraph | CPU | 1.060 | 1.00x |
| Apple M3 | Louvain | fastEmbedR | CPU | 0.293 | 3.62x |
| Apple M3 | Louvain | fastEmbedR | Metal | 0.133 | 7.97x |
| Apple M3 | Leiden | igraph | CPU | 2.136 | 1.00x |
| Apple M3 | Leiden | fastEmbedR | CPU | 0.552 | 3.87x |
| Apple M3 | Leiden | fastEmbedR | Metal | 1.434 | 1.49x |
| chiamaka | Louvain | igraph | CPU | 1.028 | 1.00x |
| chiamaka | Louvain | fastEmbedR | CPU | 0.242 | 4.25x |
| chiamaka | Louvain | fastEmbedR | CUDA | 0.100 | 10.28x |
| chiamaka | Leiden | igraph | CPU | 1.686 | 1.00x |
| chiamaka | Leiden | fastEmbedR | CPU | 0.491 | 3.43x |
| chiamaka | Leiden | fastEmbedR | CUDA | 0.695 | 2.43x |

## MNIST70k SNN graph

The real graph contains 70,000 vertices and 1,518,319 shared-nearest-neighbor
edges constructed once at k = 30. Label ARI is an external diagnostic, not an
optimization target.

| Machine | Method | Implementation | Backend | Median seconds | Modularity | Label ARI | Minimum ARI vs igraph |
|---|---|---|---|---:|---:|---:|---:|
| Apple M3 | Louvain | igraph | CPU | 8.662 | 0.879304 | 0.7825 | 1.0000 |
| Apple M3 | Louvain | fastEmbedR | CPU | 0.526 | 0.878814 | 0.8064 | 0.8604 |
| Apple M3 | Louvain | fastEmbedR | Metal | 0.346 | 0.878927 | 0.8478 | 0.8677 |
| Apple M3 | Leiden | igraph | CPU | 4.010 | 0.883520 | 0.7894 | 1.0000 |
| Apple M3 | Leiden | fastEmbedR | CPU | 2.450 | 0.883671 | 0.8096 | 0.8799 |
| Apple M3 | Leiden | fastEmbedR | Metal | 3.515 | 0.882511 | 0.8159 | 0.8952 |
| chiamaka | Louvain | igraph | CPU | 10.159 | 0.879304 | 0.7825 | 1.0000 |
| chiamaka | Louvain | fastEmbedR | CPU | 0.548 | 0.879450 | 0.7846 | 0.8610 |
| chiamaka | Louvain | fastEmbedR | CUDA | 0.231 | 0.878927 | 0.8478 | 0.8677 |
| chiamaka | Leiden | igraph | CPU | 3.286 | 0.883520 | 0.7894 | 1.0000 |
| chiamaka | Leiden | fastEmbedR | CPU | 2.402 | 0.883474 | 0.7935 | 0.8809 |
| chiamaka | Leiden | fastEmbedR | CUDA | 2.390 | 0.883093 | 0.8182 | 0.9142 |

All fastEmbedR Leiden outputs passed the connected-community invariant. The
accelerated partitions need not be identical to igraph because parallel atomic
move ordering changes valid optimization trajectories. Modularity differences
on MNIST were at most approximately 0.0011, while label ARI was not degraded.

Metal Leiden and CUDA Leiden are faster than igraph but not faster than the
package's native CPU Leiden on every machine. Louvain receives the clearest
accelerator benefit. This limitation is retained in reporting rather than
hidden by an automatic backend substitution.

## Test coverage

- canonical cliques and isolated vertices;
- weighted stochastic block graphs compared with igraph;
- resolution changes;
- disconnected-community splitting for Leiden;
- vertices incident to more than 64 candidate communities;
- unavailable CUDA/Metal requests and the no-fallback contract;
- three seeded repetitions on synthetic and MNIST70k graphs.

The full source-aware test suite passed locally. The CUDA graph-clustering suite
passed on chiamaka. The reduced `R CMD check --as-cran` run passed code,
examples, and tests; its two warnings were caused only by deliberately using
`--no-build-vignettes`, and the remaining notes concerned pre-existing
top-level manuscript files.
