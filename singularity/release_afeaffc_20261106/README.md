# fastEmbedR main image, 6 November 2026

The source is `tkcaccia/fastEmbedR` main commit
`afeaffc39a607c00db5899c284451c6cdbf741bb`. The R source archive
was built and checked on Silvano's Mac before transfer. The immutable image
was built on an allocated HPC CPU node by Slurm job 1592155. Its final path
is `/scratch/firenze/NN/singularity/release_afeaffc_20261106/fastembedr_afeaffc_20261106.sif`.
The SHA-256 in `image-final.sha256` was calculated inside that compute job;
no large image was hashed on the HPC login node. The source and image labels
agree with the main commit and package archive checksum.

The GPU pilot is job 1592858. It is one bounded resident 160-row, 3D UMAP
fit on two L40S GPUs. It verifies the image digest inside its allocation,
assigned GPU UUIDs, result shape and reference preservation, scheduler
warning handling, and owned process and GPU-context cleanup. Wider GPU
benchmarks must wait for its terminal audit. The pilot does not read any
file-backed dataset or run a streaming algorithm.

The old image and previous source-locked jobs are untouched. The build script
checks the previous image and all three source archives on its compute node.
