# fastEmbedR 535d071 HPC image

The package source is `tkcaccia/fastEmbedR` main commit
`535d071849945db3fa550d3c50f80633b91748cc`.
The `R CMD build` archive SHA-256 is
`9591bc47b952993f296bd678479245038ab5823097a33af9a18e0bb6670eb451`.
The definition reuses the exact faissR and gpuinfo archives from the prior
release. The source and dependency hashes are checked inside the build.

The candidate corrects the explicit CPU PCA worker cap found by the
source-locked Fashion-MNIST scaling audit. A CPU-only isolated build passed
its 4, 8, 16 and 32 worker probe and focused installed-package tests on
HPC compute nodes. The failed original cases are preserved separately.

Build job `1606224` creates
`/scratch/firenze/NN/singularity/release_535d071_20261107/fastembedr_535d071_20261107.sif`.
The build script hashes the large base and final images only on its Ada
compute node. Check its terminal scheduler state, image digest and embedded
source identity, then run a separate CPU pilot before any real-data rerun.
No file-backed or SSD-streaming scientific work is permitted on HPC.
