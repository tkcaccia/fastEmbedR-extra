# fastEmbedR benchmark

Reproducible benchmark and validation workflows for
[`fastEmbedR`](https://github.com/tkcaccia/fastEmbedR).

This repository is intentionally separate from the installable R package. It
contains benchmark code, dataset manifests, preprocessing instructions,
environment recipes, Slurm launchers, validation oracles, and aggregation
scripts. It does **not** redistribute raw benchmark datasets, credentials,
container images, or large result archives.

## Repository boundary

- Package source and user documentation:
  [`tkcaccia/fastEmbedR`](https://github.com/tkcaccia/fastEmbedR)
- Benchmark protocols and reproducibility code: this repository
- Raw data: obtained by each user from the original provider under that
  provider's license and access conditions
- Manuscript source and journal deliverables: maintained outside both GitHub
  repositories

The separation keeps the Bioconductor package repository small while making
the computational claims auditable.

## What is included

- `tools/hpc_embeddings/`: publication CPU/CUDA/Metal drivers, isolated
  workers, Slurm launchers, quality metrics, and backend agreement tests.
- `tools/multicore_scaling/`: the 1/2/4/8/16-worker strong-scaling release
  gate, stage-level timers, peak-memory records, BLAS interaction checks, and
  an exclusive-node Slurm launcher.
- `tools/benchmark_*.R`: focused timing, accuracy, approximation, and scaling
  experiments.
- `tools/reproducibility/`: lightweight environment specification.
- `tools/manuscript/`: aggregation and figure-building code that consumes a
  local result archive; no manuscript text or figures are stored here.
- `examples/`: small entry-point benchmark examples.
- `data-manifests/`: source inventory and redistribution notes.
- `DATASETS.md`: expected local layout and acquisition policy.

## Data policy

Do not commit benchmark `.RData`, `.rds`, `.npz`, image archives, ImageNet
features, or provider downloads. Place data under a local `Data/` directory or
set `FASTEMBEDR_DATA_ROOT`. `Data/`, results, caches, credentials, and
Singularity/Apptainer images are ignored by Git.

For datasets that cannot legally be redistributed, this repository provides
only:

1. the original source or accession;
2. expected dimensions and labels;
3. preprocessing instructions;
4. a manifest/checksum mechanism for locally prepared files; and
5. scripts that fail clearly when the user has not supplied the data.

See [DATASETS.md](DATASETS.md).

## Quick validation

Install `fastEmbedR` separately, then run a small public-data check:

```bash
Rscript tools/validate_reference_implementations.R \
  --out-dir=results/reference_validation \
  --threads=2 \
  --seed=4 \
  --perplexity=10 \
  --k=31
```

The publication workflow is documented in
[`tools/hpc_embeddings/README.md`](tools/hpc_embeddings/README.md). Before
launching Slurm jobs, edit the site-specific account, partition, image, data,
and output paths. Never submit jobs merely by cloning this repository.

## Reproducibility contract

Every publication run should record:

- the `fastEmbedR` and benchmark-repository commit hashes;
- package, R, compiler, CUDA, Metal, FAISS, cuVS, RAFT, and FFT versions;
- CPU/GPU model and allocated thread/device count;
- dataset identity, dimensions, precision, and local checksum;
- seed and complete method parameters;
- requested and observed backend;
- status and error text; and
- total public-function runtime, memory, and quality metrics.

Direct-Python fit time and R-mediated total-call time are different timing
boundaries and must remain in separate columns.

## License

Benchmark code and documentation in this repository are MIT licensed unless a
file states otherwise. Dataset licenses are independent and are not granted by
this repository. Third-party software remains under its own license.
