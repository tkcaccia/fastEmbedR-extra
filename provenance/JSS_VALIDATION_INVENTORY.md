# JSS validation inventory

The canonical comprehensive campaign is
`benchmarks/linux/jss-review-validation/`.

It contains:

- strict CPU and CUDA preflight validation;
- a staged, self-submitting Slurm controller with bounded waves;
- campaign manifests and an append-only job ledger;
- t-SNE affinity-support and long-run numerical validation;
- fuzzy UMAP and compact-support t-SNE backend-quality experiments;
- observed nearest-neighbor recall diagnostics;
- held-out transformation and landmark-reconstruction experiments;
- CPU strong-scaling, PCA timing, and PCA accuracy experiments;
- CPU/CUDA component-level force, gradient, trajectory, and pathology tests;
- timing and host/GPU memory measurement helpers; and
- aggregation plus a strict final audit.

The checksum manifest `FILES.sha256` covers every campaign source file. Each
runtime campaign additionally records the container image and installed
fastEmbedR shared-library SHA-256 values obtained from matching CPU and CUDA
preflights.

The following are intentionally not tracked:

- raw or restricted datasets;
- generated KNN, PCA, and Python interchange objects;
- container images;
- credentials or host access configuration;
- worker logs and replicate-heavy raw results; and
- manuscripts or submission correspondence.

Those artifacts are represented by manifests, checksums, public acquisition
instructions where licensing permits, and the permanent result archive.
