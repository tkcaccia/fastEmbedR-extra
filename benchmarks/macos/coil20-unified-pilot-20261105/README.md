# COIL20 unified-API Mac pilot, 5 November 2026

This is a development pilot, not a JSS benchmark estimate. It ran in
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-coil20-unified-pilot-20261105`
on Silvano's single-GPU Mac. The package was the isolated R 4.6 candidate
archive SHA-256
`18902d45dd0a6d0278f52d3712e8892a38d6ec16516644fc9ee2114f5be92973`;
the COIL20 input SHA-256 was
`8e53030869bcfbc228edc06ca970e69b78ddae13fb188327e8899194d5841d66`.
The complete 1,440-row, 16,384-feature input was reduced to 30 PCA scores
on one CPU core. Embedding and clustering comparisons used the same PCA
scores. Each case used seed 4, and embedding quality sampled 600 rows.
The run completed in 7.582 seconds with no failed case or timeout. The
bounded runner allowed 30 minutes and 16 GiB of R vector memory.

| Case | Seconds | Sampled trustworthiness | Label accuracy | ARI |
| --- | ---: | ---: | ---: | ---: |
| PCA CPU 1 | 0.302 | | | |
| t-SNE CPU 1, 2D | 3.506 | 0.98739 | 0.86667 | |
| t-SNE Metal, 2D | 0.701 | 0.98730 | 0.86667 | |
| UMAP CPU 1, 2D | 0.736 | 0.97971 | 0.88833 | |
| UMAP CPU 4, 2D | 0.146 | 0.97546 | 0.89167 | |
| UMAP Metal, 2D | 0.343 | 0.98014 | 0.90000 | |
| Louvain CPU 1 | 0.004 | | | 0.67798 |
| Louvain CPU 4 | 0.013 | | | 0.65953 |
| Louvain Metal | 0.024 | | | 0.66941 |
| Leiden CPU 1 | 0.007 | | | 0.66750 |
| Leiden CPU 4 | 0.021 | | | 0.66066 |
| Leiden Metal | 0.052 | | | 0.66761 |

The clustering graph was built once from the PCA scores and its construction
time is excluded from clustering case timings. These millisecond clustering
measurements are too short for speed conclusions. CPU 4 fits are parallel
within one resident graph; this is separate from the file-backed full-graph
parallel route, whose measured overhead remains unresolved. The Metal UMAP
Fashion-MNIST paired quality gap is still open despite this COIL20 result.

The exact runner and R script are included. Script SHA-256 values: R
`b01ff10eec29491e653e2772b9e80427906a9bcd3972d9beafe0421f432625c1`;
runner
`d6b46095303e5129d715f2c551ddcb29135c67e0e8f0f1745892376ca8e80501`.
Small logs and metrics are copied here; the saved fit objects remain on Mac
under Stefano.
