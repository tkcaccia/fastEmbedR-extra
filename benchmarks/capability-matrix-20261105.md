# Capability qualification ledger

The adjacent CSV enumerates all 140 combinations of seven method/output
variants, five hardware routes, two storage modes, and two fit scopes.
Metal has one GPU only. `cuda_multi` means a coordinated fit across at
least two CUDA devices, not multiple independent fits.

This is an **interim qualification ledger**. `unqualified` means current
evidence does not yet establish the goal's real-device correctness,
quality, memory, and no-fallback requirements; it does not assert that
the code route is absent or broken. `failing` identifies a measured
quality or scaling problem. The final release ledger must resolve every
`unqualified` row to `verified`, `failing`, `limited by measured resources`,
or `not implemented`, with a direct evidence path and exact source version.
No row is currently marked `verified` from one-seed development pilots.

The ledger is not a promise that every combination has a common optimal
parameter set. Benchmark profiles must specify PCA rank and, for t-SNE
and UMAP, 2D/3D output and valid neighborhood parameters for each input.
All-row output is required for landmark routes. Formal file-backed work
runs outside UCT HPC; its HPC rows must be qualified on the Mac or another
permitted host rather than scheduled on the cluster.
