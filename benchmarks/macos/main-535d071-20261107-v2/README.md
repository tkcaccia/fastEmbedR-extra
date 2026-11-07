# Mac resident panel, worker v2

This is a fresh 693-case panel for package main
`535d071849945db3fa550d3c50f80633b91748cc`. It preserves all failed
v1 results and uses new result directories and case IDs. The v1 queue
stopped after its first three cases because the first `nrow()` call on a
loaded `float32` object returned `NULL` before the `float` namespace's
methods were registered. A prefix-only Mac diagnostic reproduced the
failure and showed that explicitly loading `float` before the dataset
resolved it. The v2 worker does so while retaining float32 data.

The immutable plan has eleven datasets, PCA, 2D/3D t-SNE, 2D/3D UMAP,
Leiden and Louvain, three seeds, CPU1/CPU4/Metal1: 693 resident full-data
cases. There is no SSD streaming or spill in this cohort. The Mac has one
GPU. Long 3D t-SNE cases have a 7,200-second bound; other cases have the
original 1,800-second bound. One R worker has a 96 GiB vector limit on
the measured 256 GiB Mac. The serial queue stops on uncertain cleanup,
timeout, >1 GiB new swap, <100 GiB free disk or three consecutive failures.

`build_panel.py` checks the complete old case roster and dataset inventory
and emits new manifests, queue, plan identity, and one separately named
COIL20 CPU pilot case. `preflight.py` verifies all inputs and installed
package identities before any calculation. The pilot must pass before the
full queue starts. Every case then verifies its input and package again,
records actual backend, timing, quality, memory, swap and cleanup, and
keeps failures. Metal UMAP reports CPU warm and Metal optimizer epochs.
The final `audit_panel.py` must accept every case before publication use.
Do not pool this cohort with the older package or worker versions.

The v2 worker verifies input hashes and shapes, but does not assert the
loaded or preprocessed `float32` class. Its output auditor cannot certify
precision from the recorded metrics. It also leaves t-SNE automatic
configuration enabled, while the HPC matched v3 worker disables it and
fixes the early exaggeration schedule. These t-SNE timings are not a
matched cross-machine comparison. Keep the active source-locked scripts and
results unchanged; a later versioned worker must enforce the shared
scientific controls, precision, effective workers, and write-stage timing.
