# Staged real-dataset CUDA qualification case

This resident-only COIL20 2D UMAP case uses two allocated L40S GPUs and the
read-only image built from fastEmbedR main commit
`afeaffc39a607c00db5899c284451c6cdbf741bb`. Its route manifest admits
only this method, dataset, GPU count and full-data fit. File-backed input,
streamed algorithm state and absent Slurm allocation are rejected before the
fit. The R worker checks observed backend, both devices, output dimensions,
and finite coordinates. The outer process group has a three-minute deadline,
bounded shutdown, assigned-device context checks and fail-closed telemetry.

The staged case is **not submitted** until the terminal evidence from new-image
GPU pilot 1592858 is audited. Local admission and twelve lifecycle/mapping
tests passed. This case is a real-data route qualification, not a broad GPU
benchmark or a claim of useful two-GPU speedup. Each later method needs its
own reviewed route and qualification.
