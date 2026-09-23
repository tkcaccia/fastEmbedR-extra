# fastEmbedR-extra

Reproducible benchmark code, compact result tables, and figure-generation
workflows for [`fastEmbedR`](https://github.com/tkcaccia/fastEmbedR).

This repository is deliberately separate from the installable R package. It
does not contain the manuscript, raw datasets, credentials, container images,
or large replicate-level result archives.

## Repository layout

| Path | Purpose |
|---|---|
| `benchmarks/macos/` | Native macOS CPU and Metal launchers |
| `benchmarks/linux/` | Linux CPU and CUDA launchers, including Slurm and Apptainer/Singularity setup |
| `benchmarks/shared/` | Platform-independent measurement engine and quality metrics |
| `benchmarks/legacy/fastEmbedR-benchmark/` | Complete migrated source and history of the former standalone benchmark repository |
| `analysis/` | Raw-result aggregation and deterministic table/figure builders |
| `results/aggregate/` | Compact machine-readable benchmark summaries |
| `results/figures/` | Figures generated from the aggregate CSV files |
| `results/tables/` | Tables generated from the aggregate CSV files |
| `data-manifests/` | Dataset identities and acquisition notes, without raw data |
| `config/` | Immutable release-lock template |
| `provenance/` | Checksums and source identities for bundled artifacts |

The macOS and Linux workflows are intentionally distinct. They share the R
measurement engine but do not share launchers, hardware assumptions, thread
configuration, accelerator checks, or output roots.

## Integrated benchmark repository

The former `tkcaccia/fastEmbedR-benchmark` repository was merged here on
2026-09-23. Its complete source tree, including release-validation,
multicore-scaling, dataset-manifest, and historical publication workflows, is
preserved under `benchmarks/legacy/fastEmbedR-benchmark/`. The merge retains
the original Git history. New benchmark development belongs in this
repository; the standalone repository has been retired.

## macOS benchmark

The native macOS workflow evaluates fastEmbedR CPU and Metal routes. It does
not use a Linux container or Slurm.

```bash
cd fastEmbedR-extra
FASTEMBEDR_PACKAGE_ROOT=/path/to/fastEmbedR \
FASTEMBEDR_DATA_ROOT=/path/to/Data \
bash benchmarks/macos/run_cpu_metal.sh
```

See [`benchmarks/macos/README.md`](benchmarks/macos/README.md).

## Linux benchmark

The Linux workflow separates multicore CPU and CUDA jobs. The supplied Slurm
scripts use the UCT HPC paths from the publication environment, but all
site-specific settings are collected in the Linux scripts and documented in
[`benchmarks/linux/README.md`](benchmarks/linux/README.md).

After filling `config/release_lock.env`, synchronize without submitting jobs:

```bash
FASTEMBEDR_PACKAGE_ROOT=/path/to/fastEmbedR \
HPC_ROOT=/path/to/hpc/mirror \
bash benchmarks/linux/sync_to_hpc.sh
```

On the Linux HPC login node:

```bash
cd /scratch/firenze/NN
bash current_fastembedr_validation/submit_current_validation_hpc.sh
```

## JSS reviewer-validation campaign

The complete release-validation campaign requested for the Journal of
Statistical Software submission is maintained under
`benchmarks/linux/jss-review-validation/`. This is the canonical source for
the staged Slurm controller, scientific workers, numerical component tests,
aggregation, and strict final audit. The controller submits only one bounded
wave at a time and records the complete job graph in `jobs.tsv`.

Synchronize the repository-owned campaign without submitting jobs:

```bash
HPC_ROOT=/path/to/hpc/mirror \
bash benchmarks/linux/jss-review-validation/sync_to_hpc.sh
```

After strict CPU and CUDA preflights pass, start it on the HPC with:

```bash
cd /scratch/firenze/NN
bash \
  benchmark_scripts/fastembedr_jss_review_validation/submit_complete_campaign.sh
```

Each launch has an isolated campaign manifest, input cache, result tree,
submission ledger, and final audit. The repository does not contain datasets,
container images, credentials, or replicate-heavy raw outputs.

## Rebuild tables and figures

The committed figures and tables are generated only from the compact CSV files
under `results/aggregate/`:

```bash
make tables
make figures
make validate
```

Raw result archives are aggregated separately:

```bash
Rscript analysis/aggregate_linux_results.R \
  /path/to/fastEmbedR-results \
  results/aggregate

Rscript analysis/aggregate_macos_results.R \
  /path/to/macos-embedding-results \
  /path/to/macos-graph-results \
  results/aggregate
```

Direct-Python fit time, Python process-wall time, R-mediated total-call time,
and R public-function total-call time remain separate fields. They must not be
silently merged into one timing boundary.

## Results and data policy

The files in `results/` are compact derived summaries and publication figures.
They are not a substitute for the immutable replicate-level result archive.
Each release-level analysis must record the source tag and commit, benchmark
commit, source/package/shared-library/container SHA-256 values, hardware,
dependencies, dataset checksums, seeds, requested and observed backends, and
the permanent result-archive DOI.

Raw benchmark datasets are not redistributed. See [DATASETS.md](DATASETS.md).

## License

Repository-owned benchmark and analysis code is MIT licensed. Dataset and
third-party software licenses remain independent.
