# Source-locked CPU32 candidate, 24 October 2026

This is a **candidate** image for CPU scaling checks. It does not replace
`fastembedr_cuda.sif` and is not a UCT GPU qualification. UCT GPU submissions
remain paused pending explicit user release and administrator approval.

## Identity

| Item | Identity |
|---|---|
| fastEmbedR source | `c8413681aeb7d42747f2992d38faab4651e348c5` |
| faissR source | `7a22de471eb6d83dd9d1873ef0f89401ea8f11f5` |
| gpuinfo installed | `0.2.0` from the pinned base image |
| base SIF SHA256 | `91387e35888bdd61fbd75bff7add5cf4fca7b3b4bdc15522ab3eade78ea8ea2e` |
| candidate SIF SHA256 | `dd9ed112c638b53f06d7baed51a17de515fa7d58d730c8352fa6fd732ffd265a` |
| candidate SIF bytes | `8,885,276,672` |

The clean Git-tree source archives and their hashes are recorded in
[`release_inputs/`](release_inputs/). Build the archives from those exact
commits, verify `SHA256SUMS`, and use
[`fastembedr_cpu32.def`](fastembedr_cpu32.def) on Chiamaka. The definition
starts from the pinned local base image and installs faissR 0.1 and
fastEmbedR 0.1. It verifies the archives, installed package versions,
and shared-library checksums before creating the candidate SIF.

The candidate is retained at:

- Chiamaka: `/mnt/sata_ssd/fastEmbedR/singularity/cpu32_20261024/fastembedr_cpu32.candidate.sif`
- UCT HPC: `/scratch/firenze/NN/singularity/fastembedr_cpu32.candidate_20261024.sif`

The HPC copy was checked against the Chiamaka SIF SHA256. The image labels
contain both source commits and the base-image hash. `ldd` found no missing
libraries in the installed faissR and fastEmbedR DLLs. No GPU route was run
on the UCT HPC.

## CPU validation

[`smoke_cpu.R`](smoke_cpu.R) can run without Slurm. It checks installed
versions, faissR CPU HNSW, complete file-backed PCA output with 8 and 32
workers, small-graph t-SNE agreement, a 32,768-row sparse t-SNE step with
32 effective workers, and bit-identical synchronized UMAP output at 1 and
32 workers. It passed on Chiamaka and in UCT `ada` job **1526755**
(exit 0). The latter used [`smoke_cpu.sbatch`](smoke_cpu.sbatch).
Small output and timings are in [`validation/`](validation/).

Three independent UCT `ada` jobs then ran the existing 10M-row Deep1B
throughput diagnostic from the same image. All checked 10 million output
rows (80,000,000 float32 bytes) before removing the layout payload.

| Job | Method | Native workers | Elapsed in R (s) | Peak RSS (MiB) |
|---|---|---:|---:|---:|
| 1526757 | PCA, concurrent | 32 | 17.526 | 400.8 |
| 1526758 | FFT t-SNE, 2 iterations | 32 | 1.305 | 744.4 |
| 1526759 | synchronized UMAP, 2 epochs | 32 | 4.941 | 572.7 |
| 1526760 | PCA, isolated repeat | 32 | 7.445 | 400.4 |

The concurrent PCA run overlaps the other graph reads and is not a clean
scaling comparison. Its isolated repeat is close to the earlier 32-worker
diagnostic. The short t-SNE and UMAP profiles agree with earlier timings;
they are **not** full fits or quality comparisons. The profile uses existing
10M-row source, graph, and initialization files on the HPC. It is not a
self-contained data-preparation workflow. The exact-image runner is
[`profile_cpu32_image.sbatch`](profile_cpu32_image.sbatch); its R workload
is [`profile_cpu32.R`](../../benchmarks/linux/massive-data/deep1b/profile_cpu32.R).

No GPU run, full-fit neighborhood-quality assessment, or matched 16-versus-32
core publication benchmark is claimed from these candidate checks.
