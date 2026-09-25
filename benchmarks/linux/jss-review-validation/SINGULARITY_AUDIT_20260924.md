# Publication-image audit: 2026-09-24

## Image identity

- Remote path:
  `/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.sif`
- SHA-256:
  `a28f39721102dedc641384f477a055300fe1c1b7ed40101a536d2ec954f96bd5`
- Operating system: Debian Linux
- R: 4.6.1
- fastEmbedR: 0.1, source commit
  `521f6ff9f88c66086813fa6c81bac19a197111c3`
- Python: NumPy 2.2.6, SciPy 1.16.3, scikit-learn 1.9.0,
  openTSNE 1.0.4, umap-learn 0.5.12, and RAPIDS cuML 26.06
- CUDA architectures: 75, 80, 86, 89, 90, and 120

## Functional CUDA validation

The image ran real GPU calculations for all three principal native paths.
Returned metadata identified:

- PCA backend `cuda_raft_tsvd`, method `raft_tsvd`;
- UMAP backend `cuda`, optimizer `clean_atomic_standard`;
- t-SNE backend `cuda`.

The smoke test synchronized the device and rejected CPU metadata. Therefore,
this was a functional CUDA test rather than a package-load or fallback test.

The installed image also contains functional direct-Python CPU and CUDA
packages, including RAPIDS cuML. The cuML 26.06 t-SNE interface accepts
`max_iter`, not the removed `n_iter` parameter; the benchmark uses
`max_iter`.

## Defects and missing comparator dependencies

1. The installed fastEmbedR binary predates the CUDA landmark t-SNE repair.
   Resident CUDA transformation returns a timed result in `value`; the old R
   assembler reads `layout`, producing an invalid projected layout. The image
   must be rebuilt from the corrected source before landmark experiments run.
2. R packages `Rtsne`, `uwot`, and `umap` are absent. The strict R comparator
   preflight must fail until all three are installed and execute finite smoke
   calculations.
3. GNU `time` is absent. The revised worker can use Slurm `sstat` instead and
   records the measurement source, but GNU `time` should be included for a
   uniform per-process peak-resident-set-size protocol.
4. The FIt-SNE executable and wrapper are present at
   `/opt/fit-sne/bin/fast_tsne` and `/opt/fit-sne/bin/fast_tsne.R`. Their
   executable checksum and source commit must be recorded in the final image
   manifest.
5. The image contains additional packages such as faissR and KODAMA that are
   not required by this publication campaign. Either build a minimal
   publication image or describe this image explicitly as a broader benchmark
   environment. Their presence must not change a fastEmbedR backend route.

## Required rebuild contract

Before starting the final campaign:

1. rebuild fastEmbedR from the corrected frozen commit;
2. install and pin `Rtsne`, `uwot`, and R `umap`;
3. retain and pin `float` and `irlba`;
4. retain the FIt-SNE wrapper and executable and record their checksums;
5. retain the tested Python CPU and RAPIDS CUDA comparator versions;
6. add GNU `time` where practical;
7. run the strict CPU comparator preflight;
8. run the strict CUDA package and cuML preflights on an allocated GPU;
9. record the image, package shared-library, suite, and comparator checksums.

The staged controller uses `afterok` for comparator preflights. A missing or
nonfunctional comparator therefore stops the campaign before any expensive
benchmark wave is submitted. No benchmark or backend may silently fall back.
