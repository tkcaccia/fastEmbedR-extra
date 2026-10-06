# CPU PCA OpenBLAS trial

Run the same script against private installations of the previous and proposed
fastEmbedR builds. Both must use the same R, host, linked BLAS, and seed. The
script generates a deterministic in-memory matrix, warms up once, then makes
three complete public `pca()` calls. It records full R-call time and the native
`prepare`, `sketch`, `project`, and `small_svd_and_scores` stages, as well as
the matrix-product route and requested/effective BLAS thread counts. It does
not save the input matrix.

```sh
R_LIBS=/path/to/previous/library Rscript run_pca.R 70000 784 previous.csv
R_LIBS=/path/to/proposed/library Rscript run_pca.R 70000 784 proposed.csv
```

Chiamaka trial, 2026-10-06: R 4.6.1, OpenBLAS 0.3.34, i7-13700,
`n.cores = 4`, rank 50. The previous native kernel used one effective BLAS
thread; the proposed OpenBLAS route used four. The medians below are from
three measured calls after one warm-up per build and shape. Individual runs
are in `results/`.

| Shape | Stage | Previous native | OpenBLAS SGEMM | Ratio |
| --- | --- | ---: | ---: | ---: |
| 20,000 x 512 | Prepare | 0.0227 s | 0.0229 s | 1.0x |
| | Sketch | 0.8364 s | 0.0296 s | 28.2x |
| | Project | 0.2387 s | 0.0350 s | 6.8x |
| | Small SVD and scores | 0.0128 s | 0.0054 s | 2.4x |
| | Complete R call | 1.118 s | 0.101 s | 11.1x |
| 70,000 x 784 | Prepare | 0.1126 s | 0.1138 s | 1.0x |
| | Sketch | 4.7817 s | 0.1464 s | 32.7x |
| | Project | 1.1971 s | 0.1486 s | 8.1x |
| | Small SVD and scores | 0.0417 s | 0.0111 s | 3.8x |
| | Complete R call | 6.167 s | 0.446 s | 13.8x |
| 1,440 x 16,384 | Prepare | 0.0448 s | 0.0471 s | 1.0x |
| | Sketch | 1.6681 s | 0.1163 s | 14.3x |
| | Project | 0.2194 s | 0.0148 s | 14.8x |
| | Small SVD and scores | 0.0915 s | 0.0898 s | 1.0x |
| | Complete R call | 2.065 s | 0.310 s | 6.7x |

Prepare centers/scales and converts the matrix to float32. Sketch multiplies
the matrix by random vectors and performs power iterations. Project forms a
QR basis and multiplies it by the input. The last native stage computes the
small singular value decomposition, scores, and loadings. Complete R call
also includes R-wrapper and native result-conversion overhead; the four
native stage medians need not sum to the median complete-call time.

The inputs are synthetic shapes, not the named benchmark datasets. For the
70,000 x 784 case, separately observed process peak RSS was 1,364,720 KiB
previously and 1,367,784 KiB with OpenBLAS. On a separate 6,000 x 128
low-rank input using the same seed, score-space relative Frobenius error was
4.47e-7 against the previous implementation after component sign alignment.
That numerical check is not a deterministic or exact-SVD reference.

## ImageNet tuning gate

`test_tuning.R` uses the 512 archived ImageNet accuracy rows in
`data/imagenet_rows.csv`, not a new random sample. The archived dense-SVD
singular values are in `data/imagenet_reference_singular_values.csv`. On
Chiamaka, the selected input reproduced those singular values to relative
difference 8.9e-16. Run the diagnostic as:

```sh
R_LIBS=/path/to/proposed/library Rscript test_tuning.R \
  /path/to/imagenet_float32.RData \
  data/imagenet_rows.csv \
  data/imagenet_reference_singular_values.csv \
  results/imagenet_tuning.csv
```

The test used the proposed OpenBLAS build, ranks 2 and 50, three seeds,
oversampling from 10 to 80,
and zero to three power iterations. `results/imagenet_tuning.csv` contains
all 96 fits. Selected median mean score-subspace cosines are:

| Rank | Oversampling | Power | Cosine | Variance gap |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 10 | 1 | 0.618 | 0.00534 |
| 2 | 20 | 1 (current) | 0.768 | 0.00355 |
| 2 | 20 | 2 | 0.911 | 0.00096 |
| 2 | 80 | 3 | 0.999 | 0.00002 |
| 50 | 10 | 1 | 0.686 | 0.04491 |
| 50 | 20 | 1 | 0.725 | 0.03877 |
| 50 | 20 | 2 (current) | 0.831 | 0.01767 |
| 50 | 80 | 3 | 0.985 | 0.00171 |

The cheaper policy loses accuracy on this fixed ImageNet sample and is not
suitable as the default. Increasing sketch width and power improves agreement
but costs more; it requires broader shape and end-to-end evaluation before a
new accuracy-oriented policy is chosen. These millisecond timings on 512 rows
are diagnostic, not a full-ImageNet performance comparison.
