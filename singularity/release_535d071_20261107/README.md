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

Build job `1606224` created
`/scratch/firenze/NN/singularity/release_535d071_20261107/fastembedr_535d071_20261107.sif`.
Its compute-node SHA-256 is
`15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2`.
The build script hashed the large base and final images only on its Ada
compute node. The terminal source identity and CPU pilot `1606228` passed.
The Fashion-MNIST 4/8/16/32-core PCA reruns and 42 COIL20 CPU cases passed
the separate compute-node result audit. The lifecycle-qualified resident
two-L40S pilot `1606281` was submitted with a ten-minute wall limit; it
must pass source/image/device/cleanup review before any broad GPU wave.
No file-backed or SSD-streaming scientific work is permitted on HPC.
