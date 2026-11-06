# fastEmbedR 77b852f HPC image candidate

This release input uses `tkcaccia/fastEmbedR` main commit
`77b852fc496ad4665969c4f6771088f5b98da4fe`, which honors an explicit
native CPU t-SNE worker count. Its `R CMD build` archive SHA-256 is
`f1c6e346f3433a3f8e62a7ec26ce614e5ae62c58b8d0aa5b798b349426212288`.
The preceding image's faissR and gpuinfo source archives are reused by exact
path and checked again during the new build. The 8.5 GB base-image and final
image hashes run inside the Ada compute allocation, never on the head node.

The CPU-only source qualification ran as jobs `1605266` and `1605291`.
The installed baseline reported two effective t-SNE workers for an explicit
eight-core request; the candidate reported eight. The focused `test-tsne.R`
file passed with one expected Metal-only skip. The full benchmark still needs
a new source-locked image and versioned pilot. Existing `7c68bc2` results
remain separate and the two failed CPU8 t-SNE pilots are preserved.

The intended output is
`/scratch/firenze/NN/singularity/release_77b852f_20261106/fastembedr_77b852f_20261106.sif`.
No scientific job should use it until the build's scheduler outcome, image
identity and compute-node checksum pass, followed by a separate CPU pilot.
No file-backed or SSD-streaming scientific work is permitted on UCT HPC.
