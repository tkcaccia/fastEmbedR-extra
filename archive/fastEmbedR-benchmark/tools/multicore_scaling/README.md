# Multicore strong-scaling release gate

This protocol measures fastEmbedR CPU scaling with 1, 2, 4, 8, and 16
requested workers on three workload profiles:

- MetRef: small, wide metabolomics matrix.
- MNIST: medium 70,000 by 784 image matrix.
- `simulated_1M_2D`: deterministic one-million-observation stress test.

The measured stages are native nearest-neighbor search, randomized-PCA
initialization, t-SNE affinity construction, t-SNE optimization, UMAP graph
construction, UMAP spectral initialization, UMAP optimization, and both full
public workflows. The t-SNE native call reports affinity and optimizer times
from inside one invocation, so no stage time is estimated by subtraction.

Primary scaling runs force BLAS to one thread while varying package workers.
A separate MNIST interaction grid varies package workers and BLAS limits. This
distinguishes useful package parallelism from nested oversubscription. UMAP's
validated CPU graph and optimizer currently cap effective workers at four; the
output records both requested and effective counts, so 8- and 16-worker points
must not be presented as 8- or 16-worker execution.

Each cell runs in a fresh R process, performs one warm-up, and records five
same-seed timing repetitions, process high-water RSS, implementation identity,
requested/effective workers, and BLAS state. The fixed KNN, PCA initialization,
and UMAP graph/initialization cache is generated once and reused by stage-only
measurements.

Submit on the HPC with:

```bash
cd /scratch/firenze/NN
sbatch benchmark_scripts/multicore_scaling/run_multicore_scaling_cpu16.slurm
```

The Slurm job requests one 16-CPU process on an exclusive node. This is
intentional: `--ntasks=16` would request 16 processes rather than the 16
threads used by one R process.
