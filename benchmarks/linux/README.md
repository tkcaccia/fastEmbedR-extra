# Linux CPU and CUDA benchmark

The Linux workflow is separate from the native macOS workflow. It uses one
immutable fastEmbedR source identity, an isolated R library, and distinct
Slurm jobs for multicore CPU and CUDA measurements.

## Site configuration

The supplied launchers reproduce the UCT HPC layout:

- base directory: `/scratch/firenze/NN`;
- data: `/scratch/firenze/NN/Data`;
- container: `/scratch/firenze/NN/singularity/fastembedr_cuda.sif`;
- results: `/scratch/firenze/NN/fastEmbedR-results`; and
- reusable inputs: `/scratch/firenze/NN/fastEmbedR-input`.

CPU jobs use the `ada` partition and CUDA jobs use one L40S GPU. Change the
Slurm account, partitions, memory, and paths explicitly for another site.

## Freeze a release

Populate `../../config/release_lock.env` with an immutable package tag,
version, full commit, release label, and result DOI. The preparation job
derives and records source, package, installed shared-library, image, and
benchmark checksums. Empty release-lock fields are rejected.

## Synchronize

From the workstation with the HPC filesystem mounted:

```bash
FASTEMBEDR_PACKAGE_ROOT=/path/to/fastEmbedR \
HPC_ROOT=/path/to/hpc/mirror \
bash benchmarks/linux/sync_to_hpc.sh
```

This copies the Linux launchers, shared measurement engine, release lock, and
a detached checkout of the locked package to
`current_fastembedr_validation/`. It does not submit jobs.

## Submit

On the HPC login node:

```bash
cd /scratch/firenze/NN
bash current_fastembedr_validation/submit_current_validation_hpc.sh
```

The dependency chain is preparation, CPU/CUDA benchmark jobs, and then the
identity/result gate. A run is valid only when the final gate writes an
`identity_validated` status.

Linux CPU and CUDA results remain separate directories under one run ID. The
analysis scripts can combine them after preserving requested and observed
backend, timing boundary, and failure status.

## Complete JSS validation

`jss-review-validation/` is the current comprehensive publication campaign.
It supplements the compact release workflow above with affinity-support,
observed-neighbor-recall, backend-quality, held-out transformation,
landmarking, strong-scaling, PCA, long-run t-SNE, numerical-component, timing,
and memory experiments.

The campaign uses a self-submitting Slurm controller. One bounded wave is
active or queued at a time, submission-limit failures are retried, all job IDs
are written to a campaign ledger, and a strict final audit rejects incomplete
evidence. See
[`jss-review-validation/README.md`](jss-review-validation/README.md).

The scripts in this repository are the source of record. Deploy them with:

```bash
HPC_ROOT=/path/to/hpc/mirror \
bash benchmarks/linux/jss-review-validation/sync_to_hpc.sh
```

The synchronization step does not run Apptainer/Singularity and does not
submit Slurm jobs.
