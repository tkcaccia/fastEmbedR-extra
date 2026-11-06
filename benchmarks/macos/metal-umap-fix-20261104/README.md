# Metal UMAP optimizer investigation, 2026-11-04

Status: unresolved. No experimental patch was integrated into the package.

Fixed input: Fashion-MNIST 5,000 rows, CPU-generated 30-neighbor graph
and spectral initialization, 400 epochs. CPU and Metal use the same graph
and initialization. Paired seeds: 4, 17, 42. The quality gate is Metal
silhouette >= CPU silhouette minus 0.01, on every seed.

Baseline Metal modes 0, 1, and 2 missed the gate. Longer optimization,
learning-rate/repulsion/negative-sampling grids, and initialization scales
also missed it. A 108-fit tuning grid had best worst-seed delta -0.01213,
still below the -0.01 gate. Repeated mode-1 fits showed output variability;
12 repeats per seed did not provide a reliable pass. Higher fixed-point
precision, exact power instead of the force approximation, and disabling
tail writes all missed the gate.

A diagnostic serial Metal kernel with CPU-compatible 64-bit random sampling
matched the CPU quality closely on a 300-row subset (CPU 0.06862, Metal
0.07147), but its 5,000-row run was too slow and was stopped. A parallel
Metal kernel with CPU-compatible random sampling still missed the 5,000-row
gate (seed 4 delta -0.02262). This points toward update concurrency or a
related optimizer dynamic as the main remaining issue; it is not proof of
a single root cause. The 5,000-row serial diagnostic was not completed.

Scripts, logs, CSV results, and source diffs for each experiment are in this
folder. The temporary compiled source/library duplicates were removed after
saving those diffs. No source-locked package or benchmark was altered.

Next: design and test a parallel optimizer with controlled update ordering.
Qualify it on the fixed-graph Fashion gate, repeatability, another dataset,
2D/3D, and timing before integrating or claiming Metal quality parity.
