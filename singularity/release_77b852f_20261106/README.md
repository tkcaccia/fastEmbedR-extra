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

Build job `1605295` completed `0:0` on an Ada compute node in 7m50s. The
compute-node image SHA-256 was
`ca7c58b98c180571e3a103258598ad7dbcb4354fb1abde3fc319aab2bc004b6b`.
The saved image labels identify package commit `77b852f` and the source
archive hash above. The resulting 9,049,350,144-byte image was made
read-only after the audit; it was never hashed on the head node.

Dependency-gated CPU pilot `1605302` completed `0:0`. It rehashed the image
inside its own compute allocation and matched the build digest, checked the
embedded commit, and ran 150-row resident Iris 3D t-SNE. The CPU backend
reported eight requested and eight effective workers, finite all-row output,
trustworthiness 0.988353 and fit time 0.463 seconds. This is image and route
qualification, not a manuscript performance result. A new source-locked
real-data cohort is still required before rerunning the failed COIL20 t-SNE
cases and combining methods in manuscript comparisons.
