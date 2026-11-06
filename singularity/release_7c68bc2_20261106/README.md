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

Build job `1604217` completed on `srvrochpc100` in 7 minutes 28 seconds
with exit code zero. The image checksum was calculated on that compute
node: `dac3a842cfbb533e57be432efa3152263c44cf30593606907bf751fc100d109c`.
The image labels identify package commit
`7c68bc2a48ff3f98d07f216db9601047951827fd` and source archive
`ba74bf2b7e24301170221abb051fca3f6f61a79d83d607452cef1e270b566df7`.
The resulting image was made read-only without hashing it on the head node.

The versioned CPU image pilot `cpu_image_pilot.sbatch` and
`cpu_image_pilot.R` ran as job `1604632` on `srvrochpc100` and completed
with exit code zero. It used the embedded package to produce finite,
all-row 3D UMAP output from Iris with CPU backend and four configured
CPU workers. The package reported 0.223 seconds elapsed for this tiny
case. This is an image smoke test, not real-data scale or publication
quality evidence. L40S work still needs a new-image resident GPU pilot
with allocation, device-use, and owned-context cleanup checks before
any broader GPU benchmark can use this image.
