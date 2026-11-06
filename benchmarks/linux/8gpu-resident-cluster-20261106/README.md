# Resident CUDA clustering beyond four devices: source qualification

The isolated package candidate is
`in-progress/fastembedr-8gpu-resident-cluster-20261106` at commit
`3294441`, based on published fastEmbedR `afeaffc39a607c00db5899c284451c6cdbf741bb`.
It removes the four-device checks from the public resident graph clustering
route, its C++ bridge, and its CUDA worker. The worker already uses dynamic
vectors for selected devices, partitions, state, and synchronization.
The new mocked API test verifies that eight requested IDs reach the
coordinated native fit together. The package documentation was regenerated
from this source with roxygen2's source loader.

The source archive SHA-256 is
`2917a495539d9c10c1082d6ff571ed26ecfbd2aeb105556a9f29319d4b80599b`.
It was installed in a **CPU-only** R 4.6 Singularity allocation on Ada,
job `1602387`, which completed with exit 0. That first test invocation
loaded the older package in the base image and printed two errors. Its
reported Slurm success is **not** a test pass; the log is retained at
`/scratch/firenze/NN/benchmarks/fastembedr_8gpu_cpucheck_20261106`.

A corrected, fail-fast invocation in job `1602428` explicitly loaded
the candidate library from that job's isolated install path, confirmed
the new device-control text in the loaded function, and ran the entire
`test-cuda-resident-multigpu-cluster.R` file with `StopReporter`.
All six focused test blocks passed and Slurm reported `COMPLETED 0:0`.
No GPU was allocated for either job. This verifies CPU compilation and
R routing, **not** CUDA compilation, eight physical GPUs, device memory,
quality, speedup, or cleanup. Commit `3294441` was pushed to fastEmbedR
main to create a source-locked CUDA image; its eight-device behavior
remains unqualified until actual device checks pass. The separate Hugging
Face eight-A100 job
`6aed848c0e0338d1bb80eb48` tests a different file-backed clustering
worker and cannot qualify this resident package route.

The public matrix-input and file-backed CUDA clustering paths still have
their own device-count and data-motion limits. This candidate addresses
only resident `graph_cluster()` on an already built graph; those other
routes remain open items in the capability matrix.
