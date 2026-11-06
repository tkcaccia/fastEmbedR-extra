# Dynamic CUDA device-count candidate (not a benchmark release)

Base package main: `7c68bc2a48ff3f98d07f216db9601047951827fd`.
Isolated candidate: `e8f0d35b58d7121beba73876dbb26d1283613b7e`.
The adjacent gzip archive contains a 58,637-byte patch with SHA-256
`29066ed0f383843b79e8247086ab5a85aaffcd61585bfc57737870da7032afd4`.
The compressed archive SHA-256 is
`5b08ec498acbc161bfacb1b64061c427e6021bce5273912cfc0241cb63fbbfab`.
It was replayed onto a fresh base checkout and all 325 tracked files
matched the candidate byte for byte. This preserves the candidate while
the local Lion volume is read-only; it does not change package main.

The candidate combines the resident CUDA PCA, t-SNE, UMAP and bounded
clustering changes with removal of remaining four-device planner limits
in file-backed CUDA UMAP, t-SNE and clustering. Native t-SNE and UMAP
workers use dynamic device vectors; the Python streamed clustering
worker accepts a device count up to the number of graph rows. The
documentation explicitly marks more-than-four-device behavior as
unqualified. It does not claim pooled VRAM for full-graph UMAP, which
replicates the layout on each GPU.

The source archive SHA-256 is
`674dc0acd8dbd3bc7afb2fbcb5d794775803356855b3c721517b652cf8ad9442`.
HPC Ada compute job `1604660` built it with CUDA and NCCL enabled
and completed with exit code zero. The installed package passed a
resident 2D/3D CPU UMAP smoke check. A local CPU fixture exercised all
eight streamed-clustering worker shards, checked eight distinct device
IDs, eight exact communities, modularity 0.875, label partition and
temporary-state cleanup. R/Python syntax and diff checks passed.
These checks do not prove any eight-GPU device route or performance.

Device qualification is pending. The separate Hugging Face eight-A100
persistent-worker job `6aed848c0e0338d1bb80eb48` is waiting for
hardware and uses a different source-locked worker candidate. It must
not be cited as a test of this integrated package. UCT HPC remains
resident-only for scientific work; no file-backed calculation from this
candidate was run there. Do not use this candidate in a manuscript
cohort or build a release image from it until real-device correctness,
quality, memory and cleanup checks pass.
