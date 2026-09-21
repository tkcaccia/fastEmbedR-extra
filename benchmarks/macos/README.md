# Native macOS benchmark

This directory contains the native Apple benchmark. It is independent from the
Linux Slurm/container workflow in `../linux/`.

The default run evaluates:

- package-native PCA on CPU and Metal;
- complete and precomputed-KNN t-SNE on CPU and Metal;
- complete and precomputed-KNN fuzzy UMAP on CPU and Metal; and
- complete and precomputed-KNN binary UMAP on CPU and Metal.

CPU measurements use the `THREADS_GRID` values, while Metal measurements use
the selected Apple GPU. The launcher fails when Metal is requested but not
available; it does not silently substitute CPU.

The launcher installs the selected fastEmbedR source into a private library
inside the run directory before measuring it. A dirty source tree is rejected
by default. `ALLOW_DIRTY=TRUE` is available only for explicitly labelled
development experiments.

```bash
FASTEMBEDR_PACKAGE_ROOT=/Users/me/src/fastEmbedR \
FASTEMBEDR_DATA_ROOT=/Users/me/Data \
THREADS_GRID=1,4 \
SEEDS=4,17,42 \
bash benchmarks/macos/run_cpu_metal.sh
```

Optional environment variables include `DATASETS`, `METHODS`, `OUT_DIR`,
`INPUT_ROOT`, `K`, `PERPLEXITY`, `TIMEOUT`, and `FORCE`. CPU runs larger than
`LOCAL_CPU_MAX_N` are skipped unless the dataset is listed in
`LOCAL_CPU_EXCEPTIONS`.

The data files must follow the layout documented in `../../DATASETS.md`.
