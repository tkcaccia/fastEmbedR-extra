# CPU clustering routes, 2 November 2026

The isolated package candidate at `in-progress/cuda-graph-options-20261102`
now carries native parallel CPU Louvain/Leiden restarts through both
`massive_cluster(massive = "auto")` when it selects resident clustering and
file-backed landmark `massive_cluster()` / `massive_cluster_landmarks()`.
The fit uses up to `min(n.cores, n_runs)` workers; `n.cores` continues to
control graph building and landmark vote assignment. A single partition
remains serial. Full-graph file-backed CPU clustering also remains serial.

Source archive SHA256:
`d2b3a59d786e9c1bb88fe1a8f08dddf2cc65438371649a9b400089b55d656239`.
The exact archive was copied to Chiamaka and installed with CUDA disabled
in `/tmp/fastembedr_cluster_route_final_20261102/library` using the
29 October Singularity image. The source archive's README contains the
corrected documentation links. The final build completed at 20:21:35 UTC.

The focused `graph-options`, `massive-cluster-restarts`, and
`massive-cluster-workers` files passed against that installation at
20:21:50 UTC. Two CUDA-only graph-option tests skipped as expected in the
CPU-only build. The new test compared serial and parallel memberships and
modularity for Louvain and Leiden in both automatic resident and file-backed
landmark workflows; it also checked one-restart worker reporting.
The package source-style and diff checks passed locally. Build and test
logs plus their checksums are in `evidence/`.

This test establishes routing and result consistency on a small graph. It
does not establish whole-workflow speedup or parallel fitting within one
partition. The earlier MNIST70k direct `graph_cluster()` scaling pilot is
separate evidence and must not be attributed to this end-to-end route.
