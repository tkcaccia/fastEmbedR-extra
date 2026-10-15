# CUDA image release recipe

`fastembedr_cuda.def` is a source-locked update of the existing Chiamaka
image. It is a **delta definition**, not a from-scratch CUDA/RAFT/cuVS
installation: the `From:` image must already contain R 4.6, the CUDA
toolchain, RAPIDS, cuGraph, NOMAD, and the other JSS comparators. Preserve
its SHA-256 in `release_inputs/source-identity.txt` as
`BaseImageSHA256=...`. The paths in `%files` point to Chiamaka's
`/mnt/sata_ssd/fastEmbedR/singularity/release_inputs/`; adapt them if
building elsewhere.

Place source archives built from the reviewed Git commits in that input
directory: `gpuinfo_0.2.0.tar.gz`, `faissR_0.99.52.tar.gz`, and
`fastEmbedR_0.1.tar.gz`. `SHA256SUMS` must list those three archive
checksums using their basenames. The identity file must also contain
`FastEmbedRCommit`, `FaissRCommit`, `GPUInfoCommit`, and
`FastEmbedRSourceSHA256`. No password, token, or input dataset belongs in
the image or this repository.

Build a candidate without touching the stable path:

```sh
singularity build --fakeroot \
  /mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.candidate.sif \
  fastembedr_cuda.def
```

The definition checks archive hashes before installation, installs all
three packages in order, refreshes embedded labels and the shared-library
checksum, and verifies R and Python imports. Also run focused CPU/CUDA
package tests and a real one-GPU file-backed fit on Chiamaka, then record
the candidate SHA-256. Use the same candidate bytes for the HPC after
validation. Replace the stable `fastembedr_cuda.sif` only after those
checks pass; never benchmark an image whose `source-identity.txt`, R
package versions, and image checksum disagree. The HPC JSS identity CSV
must name the final image SHA-256 and embedded fastEmbedR archive SHA-256.

This recipe does not establish 2/4-GPU correctness on Chiamaka's single
GPU. Test those routes separately on an allocated multi-GPU node with
the identical SIF or a byte-matched source archive.
