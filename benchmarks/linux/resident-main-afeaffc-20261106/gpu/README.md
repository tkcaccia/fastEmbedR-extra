# Staged real-dataset CUDA qualification case

This resident-only COIL20 2D UMAP case uses two allocated L40S GPUs and the
read-only image built from fastEmbedR main commit
`afeaffc39a607c00db5899c284451c6cdbf741bb`. Its route manifest admits
only this method, dataset, GPU count and full-data fit. File-backed input,
streamed algorithm state and absent Slurm allocation are rejected before the
fit. The R worker checks observed backend, both devices, output dimensions,
and finite coordinates. The outer process group has a three-minute deadline,
bounded shutdown, assigned-device context checks and fail-closed telemetry.

The source-locked case was submitted as held job **1594628**. Do not release
it until terminal evidence from new-image GPU pilot 1592858 is audited.
The job's deployed copy predates the later one-to-three-device admission and
per-device memory checks in this directory; GitHub edits do not change its
immutable staged scripts. The expanded checks passed local lifecycle and
mapping tests, but need device qualification in a new job version. This
COIL20 run is a real-data route qualification, not a broad GPU benchmark or
evidence of useful speedup. Each later method needs its own reviewed route.
