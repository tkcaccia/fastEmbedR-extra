# KODAMA shared-graph HPC handoff

## Source and image identity

- fastEmbedR base commit:
  `ef064f2a13db0b28f257bcb25bd06fd031da6da6`
- fastEmbedR source archive SHA-256:
  `e361ec54d0289af66755c882106c9f391dcd9d11e3db67e6435aa67774787ba2`
- kodama-cpp main commit:
  `f6cdef85794d94619710a35f64462c95a02005e2`
- kodama-cpp source archive SHA-256:
  `91362f22934c1a3105b7cb14390bb3b77e104e2e98b997dcf848f5a18c34d2c3`
- embedded `kodamaR` commit:
  `f6cdef85794d94619710a35f64462c95a02005e2`
- Image SHA-256:
  `f68c8cd59a03bf45666e35cf9e264221f767e763121d5bb7f2dbdfc1d8b9f604`
- Image size: `5,226,102,784` bytes
- Chiamaka image:
  `/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda_20260731_kodama_f6cdef8.sif`
- Chiamaka active link:
  `/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.sif`
- HPC image:
  `/scratch/firenze/NN/singularity/fastembedr_cuda.sif`
- Mac-mounted HPC path:
  `/Users/stefano/HPC-firenze/NN/singularity/fastembedr_cuda.sif`

The image contains fastEmbedR 0.99.0, kodamaR 0.1.0, RcppHNSW 0.7.0,
nabor 0.5.0, rnndescent 0.2.0, R 4.5.3, CUDA 13.2, and CUDA architectures
75, 80, 86, 89, 90, and 120. The pinned source SHA-256 values are
`47938dcc987279281c13abfd667660bf1b3b76af116136a27eb066ee1a4b43da`
for nabor and
`1c6b4d1bc1b4dfb8917aea1161f4d8660f1093350b684eb6908a83113176e34b`
for rnndescent. Validation used an NVIDIA GeForce RTX 5060 Ti (compute
capability 12.0, driver 595.71.05, 16,311 MiB).

## Shared-graph contract

Each dataset/backend graph is created once with:

```r
graph <- KODAMA.graph(
  data,
  k = 100L,
  backend = backend,
  n.cores = n.cores,
  seed = 4L
)
```

The checkpoint is stored at:

```text
/scratch/firenze/NN/fastEmbedR-input/kodama_graphs/<dataset>/<cpu4|cuda>/kodama_graph_k100_seed4.rds
```

PLS-LDA and KNN, all three analysis seeds, and landmark settings 10%, 20%,
50%, and default reload the same checkpoint through:

```r
fit <- KODAMA.matrix(
  data = raw_features,
  graph = graph,
  ...
)
```

Workers validate the dataset identity, dimensions, graph parameters, backend,
and presence of the new `graph` formal argument. They require
`KODAMA.matrix()` to return `graph_builds = 0` and fail rather than silently
recompute a graph.

## Chiamaka validation

Validation command:

```bash
IMG=/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda_20260731_kodama_f6cdef8.sif
STAGE=/mnt/sata_ssd/fastEmbedR/singularity/build_20260731_kodama_f6cdef8
VALIDATOR=/mnt/sata_ssd/fastEmbedR/singularity/build_20260731_graph_argument/validate_kodama_shared_graph.R

singularity exec --nv --bind "$(dirname "$VALIDATOR"):/validation_input:ro" \
  --bind "$STAGE:/validation_output" "$IMG" \
  Rscript /validation_input/validate_kodama_shared_graph.R \
  cpu "$STAGE/validation-final-cpu"

singularity exec --nv --bind "$(dirname "$VALIDATOR"):/validation_input:ro" \
  --bind "$STAGE:/validation_output" "$IMG" \
  Rscript /validation_input/validate_kodama_shared_graph.R \
  cuda "$STAGE/validation-final-cuda"
```

Observed focused timings:

| Backend | Classifier | Graph build (s) | Matrix (s) | Internal graph builds | Accuracy |
|---|---:|---:|---:|---:|---:|
| CPU | KNN | 0.029 | 0.023 | 0 | 1.0 |
| CPU | PLS-LDA | 0.029 | 0.004 | 0 | 1.0 |
| CUDA | KNN | 0.358 | 0.022 | 0 | 1.0 |
| CUDA | PLS-LDA | 0.358 | 0.146 | 0 | 1.0 |

All four layouts were finite `400 x 2` matrices. The CPU and CUDA graph
objects were serialized, reloaded, and compared before either classifier ran.
A separate fastEmbedR CUDA UMAP smoke test also passed.

The final image was also tested with the real MetRef matrix (`873 x 375`).
Its serialized graph was reused with zero internal graph builds:

| Backend | Classifier | Graph build (s) | Matrix (s) | Best accuracy |
|---|---:|---:|---:|---:|
| CPU | KNN | 0.381 | 0.036 | 0.723 |
| CPU | PLS-LDA | 0.381 | 0.387 | 0.797 |
| CUDA | KNN | 0.301 | 0.014 | 0.727 |
| CUDA | PLS-LDA | 0.301 | 0.264 | 0.807 |

The updated image was not executed on the HPC by the build agent. The
chiamaka validation above covered graph serialization/reloading, KNN and
PLS-LDA fitting, and both UMAP/openTSNE visualization for CPU and CUDA. HPC
execution remains under the user's Slurm submission.

## HPC scripts

Synchronized source:

```text
/scratch/firenze/NN/benchmark_scripts/kodama_classifier_benchmark/
/scratch/firenze/NN/benchmark_scripts/generate_seed_grouped_kodama_jobs.sh
```

Generated jobs:

```text
/scratch/firenze/NN/kodama_classifier_jobs_by_dataset/graph_precompute/
/scratch/firenze/NN/kodama_classifier_jobs_by_dataset/seed_grouped/
```

Regenerate jobs when needed:

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/generate_seed_grouped_kodama_jobs.sh
```

Submit CPU-4 and CUDA independently:

```bash
cd /scratch/firenze/NN
bash kodama_classifier_jobs_by_dataset/seed_grouped/submit_cpu4.sh
bash kodama_classifier_jobs_by_dataset/seed_grouped/submit_cuda.sh
```

Each submitter schedules one graph job per dataset and attaches the matching
three-seed analysis array with an `afterok` dependency. The analysis array
runs KNN and PLS-LDA for 10%, 20%, 50%, and default landmarks, preserving the
existing progress/status output and the organized `fastEmbedR-results` and
`fastEmbedR-rlayout` trees.
