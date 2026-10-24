# CPU optimizer scaling, 24 October 2026

This is a CPU-only throughput diagnostic on the 10-million-row Deep1B
window, **not** a full-fit quality or JSS comparison. No UCT GPU job was
submitted. The independent Slurm jobs were 1526718 (PCA), 1526719
(t-SNE), and 1526720 (UMAP), all on `ada`; each completed with exit 0.
Each reserved 32 CPU cores, while the native worker count was set to 8,
16, or 32. Thus the table compares thread counts on a fixed allocation,
not matched 8/16/32-core Slurm allocations. The output check verified
all 10 million two-coordinate rows (80,000,000 bytes) in every run.

| Method | Workers | First run (s) | Reverse run (s) | Peak RSS range (MiB) |
|---|---:|---:|---:|---:|
| PCA, 100k-row chunks | 8 | 22.087 | 10.241 | 120.4-120.6 |
| PCA, 100k-row chunks | 16 | 7.961 | 8.284 | 123.5-123.5 |
| PCA, 100k-row chunks | 32 | 7.964 | 8.031 | 128.6-129.8 |
| FFT t-SNE, two iterations | 8 | 4.987 | 3.042 | 479.5-480.8 |
| FFT t-SNE, two iterations | 16 | 1.838 | 1.869 | 484.8-485.3 |
| FFT t-SNE, two iterations | 32 | 1.341 | 1.305 | 495.9-496.0 |
| Synchronized UMAP, two epochs | 8 | 21.639 | 5.824 | 311.1-311.8 |
| Synchronized UMAP, two epochs | 16 | 5.336 | 5.356 | 315.3-315.9 |
| Synchronized UMAP, two epochs | 32 | 5.021 | 4.998 | 323.8-324.5 |

Synchronized UMAP with one worker took 14.897 s and 307.6 MiB peak RSS
in one late, warm-cache run. It is the matched **update rule** baseline;
the ordered in-place SGD baseline is a different optimizer and is not in
this table. The UMAP runs all reported 16,217,354 positive and
64,869,410 negative updates. Local focused tests established bit-identical
1/4/32-worker output and exact interrupted-epoch restart on a small graph,
but real-data trustworthiness and neighborhood preservation remain to
be measured before calling this a quality-equivalent replacement.

Using the reverse-order runs, 16 to 32 workers reduced t-SNE elapsed
time from 1.869 to 1.305 s (1.43x). Its graph-attraction phase fell
from 1.178 to 0.625 s, while FFT repulsion stayed near 0.37 s. PCA fell
only from 8.284 to 8.031 s (1.03x); synchronized UMAP fell from 5.356
to 4.998 s (1.07x). These near-flat tails do not justify reserving 32
cores for those methods in a production campaign without further tests.
The much slower first eight-worker runs show a cache/order effect;
do not use them as clean scaling baselines.

A separate CPU phase diagnostic, job 1526735, completed with the same
installed native library and 32 allocated cores. On the reverse runs,
PCA fitting (mean plus covariance) took 8.659, 6.189, and 5.748 s at
8, 16, and 32 workers; score projection took 1.870, 1.740, and
1.780 s. Thus the plateau is visible in fitting as well as projection.
The process averaged about 7-8 CPU cores across these passes despite
more workers being requested. Serial input reads between parallel
chunks and memory traffic are plausible contributors, but this profile
does not isolate them causally. Its raw timings are in
[`raw/pca_phases/`](raw/pca_phases/).

An independent chunk-size diagnostic, CPU-only job 1526736, reused the
same pinned image and installed native library. All six runs agreed on
the two singular values to about 1e-12 and checked all 10 million output
rows before removing the score payloads. It was a single unreplicated pass,
so differences near one second need confirmation before publication.

| Workers | Chunk rows | Elapsed (s) | Peak RSS (MiB) |
|---|---:|---:|---:|
| 16 | 100,000 | 7.888 | 124 |
| 16 | 500,000 | 7.787 | 275 |
| 16 | 1,000,000 | 8.323 | 463 |
| 32 | 100,000 | 7.738 | 130 |
| 32 | 500,000 | 6.894 | 279 |
| 32 | 1,000,000 | 6.745 | 466 |

Larger chunks reduce the 32-worker PCA time by about 13% relative to
100,000-row chunks. The fastest 32-worker run is about 13% faster than
the fastest 16-worker run, but uses more core-seconds and roughly 191
MiB more peak RSS. Accordingly, the CPU benchmark runner now selects
1,000,000-row PCA chunks only for an explicitly requested 32-core run;
other CPU counts retain 100,000 rows. The chunk size is part of resume
identity and is reported in PCA metrics. Raw data and the profile script
are in [`raw/pca_chunks/`](raw/pca_chunks/) and
[`profile_pca_chunks_cpu32.R`](../../profile_pca_chunks_cpu32.R).

The pinned source archive SHA256 is
`7f1b2c2c82eae9fe88b05721ed635d5636fafb32e32e10090e4aa584e799b072`.
The local working tree subsequently gained an explicit non-finite-gradient
guard; these measurements belong to the archive above, not that later
working tree. The guard does not change finite gradients, but a final
publication campaign needs one rebuilt and requalified source identity.
The image SHA256 is
`91387e35888bdd61fbd75bff7add5cf4fca7b3b4bdc15522ab3eade78ea8ea2e`.
All three isolated CPU installs produced the same native-library SHA256,
`eeeba1dac18960c996297f04d75a36142638969dfc764d3c456345a05f2ec79e`.
The benchmark source and checksum manifest are
[`profile_cpu32.R`](../../profile_cpu32.R),
[`profile_cpu32.sbatch`](../../profile_cpu32.sbatch), and
[`profile_cpu32.SHA256SUMS`](../../profile_cpu32.SHA256SUMS).
Per-case metrics, phase timings, `/usr/bin/time -v`, and build identity
are retained in [`raw/`](raw/). Layout payloads were checked and then
removed; the original input, graph, and PCA initialization were not
deleted.
