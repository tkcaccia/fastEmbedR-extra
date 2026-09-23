# KODAMA MetRef validation on chiamaka

> **Scope warning:** this document describes an `M=10`, `Tcycle=10` smoke
> validation of the July 24 container. It does not reproduce the accepted
> MetRef PLS-LDA result. For the audited `M=100`, `Tcycle=100` reference,
> exact parameters, renderer provenance, and corrected code, use
> `KODAMA_METREF_PLSLDA_REFERENCE_HANDOFF.md` in the same directory.

## Outcome

The current KODAMA installation in the latest fastEmbedR Singularity image was
validated on the complete MetRef dataset with CPU and CUDA backends.

- Date: 2026-07-25
- Host: `chiamaka@137.158.224.178`
- Remote hostname: `icgeb-bioinformatics-unit`
- GPU: NVIDIA GeForce RTX 5060 Ti, 16,311 MiB
- NVIDIA driver: 595.71.05
- Compute capability: 12.0
- R: 4.5.3
- kodamaR: 0.1.0
- fastEmbedR: 0.99.0
- Final status: all eight classifier/backend/visualization combinations succeeded

## Image and data

Image alias:

```text
/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.sif
```

Resolved image:

```text
/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda_20260724_landmark.sif
```

The image was built on 2026-07-24 at 19:50 and was the newest `.sif` in the
directory at validation time.

MetRef input:

```text
/mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef.RData
```

The file was copied from:

```text
/Users/stefano/Documents/fastEmbedR/Data/MetRef/MetRef.RData
```

It contains `dataset$data` with 873 samples and 375 variables and
`dataset$labels` with 22 classes.

## Exact command

```bash
ssh chiamaka@137.158.224.178

STAMP=20260725_1014_final \
KODAMA_M=10 \
KODAMA_TCYCLE=10 \
/mnt/sata_ssd/fastEmbedR/tools/run_kodama_metref_chiamaka.sh
```

The launcher invokes:

```bash
OMP_NUM_THREADS=4 \
OPENBLAS_NUM_THREADS=4 \
MKL_NUM_THREADS=4 \
KODAMA_M=10 \
KODAMA_TCYCLE=10 \
singularity exec \
  --nv \
  --cleanenv \
  -B /mnt/sata_ssd:/mnt/sata_ssd \
  /mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.sif \
  Rscript \
  /mnt/sata_ssd/fastEmbedR/tools/validate_kodama_metref_chiamaka.R \
  /mnt/sata_ssd/fastEmbedR/results/kodama_metref_20260725_1014_final \
  /mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef.RData
```

## Parameters

The smoke validation used all 873 samples as landmarks.

```text
M = 10
Tcycle = 10
ncomp = 50
landmarks = 873
graph.neighbors = 100
knn.k = 30
perplexity = 30
metric = euclidean
seed = 4
CPU threads = 4
CUDA device = 0
UMAP epochs = 200
openTSNE iterations = 500
visual.init = TRUE
apply.kodama.dissimilarity = TRUE
```

This is a functional smoke validation, not the final publication benchmark.
An earlier run with `M=100` and `Tcycle=20` was preserved at
`/mnt/sata_ssd/fastEmbedR/results/kodama_metref_20260725_094322`; its CPU
PLS-LDA stage was stopped after more than 20 minutes. Reducing `M` and
`Tcycle` made it possible to validate every code path without changing the
classifier or visualization implementation.

## Essential R code

```r
library(kodamaR)
library(fastEmbedR)

load("/mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef.RData")
x <- as.matrix(dataset$data)
labels <- as.factor(dataset$labels)

fit <- KODAMA.matrix(
  data = x,
  M = 10L,
  Tcycle = 10L,
  ncomp = 50L,
  landmarks = nrow(x),
  n.cores = 4L,             # use 1L with backend = "cuda"
  graph.neighbors = 100L,
  knn.k = 30L,
  metric = "euclidean",
  classifier = "pls_lda",   # also tested with "knn"
  backend = "cpu",          # also tested with "cuda"
  seed = 4L,
  visual.init = TRUE,
  progress = FALSE,
  apply.kodama.dissimilarity = TRUE
)

tsne_layout <- KODAMA.visualization(
  x = fit,
  method = "opentsne",
  init = fit$visual_init$opentsne,
  k = 30L,
  metric = "euclidean",
  backend = "cpu",
  n.cores = 4L,
  gpu.device = 0L,
  n.iter = 500L,
  perplexity = 30,
  seed = 4L
)

umap_layout <- KODAMA.visualization(
  x = fit,
  method = "UMAP",
  init = fit$visual_init$umap,
  k = 30L,
  metric = "euclidean",
  backend = "cpu",
  n.cores = 4L,
  gpu.device = 0L,
  n.epochs = 200L,
  seed = 4L
)
```

Important API detail: the accepted t-SNE method string is lowercase
`"opentsne"`. Passing `"openTSNE"` fails immediately with:

```text
'arg' should be one of "UMAP", "t-SNE", "opentsne"
```

## Measured results

| Backend | Classifier | Visualization | Core sec | Visualization sec | Total sec | Trust | Preserve@15 | Silhouette | Label KNN accuracy |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| CPU | KNN | openTSNE | 28.978 | 0.581 | 29.559 | 0.869 | 0.368 | 0.008 | 0.630 |
| CPU | KNN | UMAP | 28.978 | 0.134 | 29.112 | 0.786 | 0.239 | -0.049 | 0.550 |
| CPU | PLS-LDA | openTSNE | 283.206 | 0.577 | 283.783 | 0.910 | 0.444 | 0.417 | 0.884 |
| CPU | PLS-LDA | UMAP | 283.206 | 0.128 | 283.334 | 0.815 | 0.279 | 0.398 | 0.828 |
| CUDA | KNN | openTSNE | 0.590 | 0.152 | 0.742 | 0.876 | 0.374 | -0.013 | 0.624 |
| CUDA | KNN | UMAP | 0.590 | 0.012 | 0.602 | 0.807 | 0.257 | -0.068 | 0.567 |
| CUDA | PLS-LDA | openTSNE | 13.238 | 0.084 | 13.322 | 0.909 | 0.441 | 0.446 | 0.889 |
| CUDA | PLS-LDA | UMAP | 13.238 | 0.011 | 13.249 | 0.830 | 0.308 | 0.405 | 0.850 |

CUDA reduced KNN core time by approximately 49.1-fold and PLS-LDA core time
by approximately 21.4-fold in this smoke run. These are single-run elapsed
times and should not be presented as publication estimates without repeated
runs.

The PLS-LDA variants gave higher label-aware quality than KNN variants on
MetRef. CPU and CUDA quality values were close, but the layouts were not
geometrically identical. Procrustes agreement was not measured in this smoke
test.

## Result locations

Remote complete result directory:

```text
/mnt/sata_ssd/fastEmbedR/results/kodama_metref_20260725_1014_final
```

Local mirror:

```text
/Users/stefano/Documents/umap/results/kodama_metref_chiamaka_20260725_1014_final
```

Important files:

```text
kodama_metref_results.csv
kodama_metref_core_timing.csv
kodama_metref_complete.rds
run_manifest.txt
system_info.txt
sessionInfo.txt
kodama_diagnostics.txt
run.log
objects/*.rds
plots/*.png
```

Source scripts:

```text
Local:
/Users/stefano/Documents/umap/tools/validate_kodama_metref_chiamaka.R
/Users/stefano/Documents/umap/tools/run_kodama_metref_chiamaka.sh

Remote:
/mnt/sata_ssd/fastEmbedR/tools/validate_kodama_metref_chiamaka.R
/mnt/sata_ssd/fastEmbedR/tools/run_kodama_metref_chiamaka.sh
```

## Native CUDA linkage observed

`KODAMA.diagnostics()` reported that `kodamaR.so` is linked to:

```text
libcublas.so.13
libcublasLt.so.13
libcufft.so.12
libcudart.so.13
libgomp.so.1
libstdc++.so.6
```

No CPU fallback was reported for the CUDA runs.
