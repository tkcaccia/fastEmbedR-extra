# fastEmbedR 7c68bc2 Singularity image

This image is built from GitHub `tkcaccia/fastEmbedR` main commit
`7c68bc2a48ff3f98d07f216db9601047951827fd`, with the same
versioned faissR and gpuinfo sources used by the preceding image.
The `R CMD build` package archive has SHA-256
`ba74bf2b7e24301170221abb051fca3f6f61a79d83d607452cef1e270b566df7`.
The source identity and all three input hashes are in `release_inputs`
on HPC scratch and in the files beside this README.

Build job `1604217` was submitted to Ada with a 45-minute limit. Its
script hashes the 8.5 GB base image, checks the small source archives,
builds the image, checks the resulting image and records labels **inside
the compute-node allocation**. Do not run image checksums on the head
node. The intended immutable output path is
`/scratch/firenze/NN/singularity/release_7c68bc2_20261106/fastembedr_7c68bc2_20261106.sif`.
No CPU or GPU benchmark result should be attributed to this image until
the build is terminal, its embedded source identity is checked, and the
appropriate resident pilot and cleanup audits have passed. No
file-backed or SSD-streaming scientific job is allowed on UCT HPC.
