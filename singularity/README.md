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
package tests and `test_candidate_gpu.R` against the candidate with a
physical CUDA device on Chiamaka, then record
the candidate SHA-256. Use the same candidate bytes for the HPC after
validation. Replace the stable `fastembedr_cuda.sif` only after those
checks pass; never benchmark an image whose `source-identity.txt`, R
package versions, and image checksum disagree. The HPC JSS identity CSV
must name the final image SHA-256 and embedded fastEmbedR archive SHA-256.

Chiamaka has one GPU. Stage the byte-identical candidate on the HPC under
a separate name and use `submit_candidate_gpu_smoke.sh 2` and then `3`
on allocated L40S nodes. Set `FASTEMBEDR_IMAGE_SHA256` to the candidate
hash. The smoke uses 100,000 synthetic rows for multi-GPU kNN, PCA,
t-SNE, UMAP, Leiden, and Louvain; it checks full-row outputs and
per-device work. Failed runs retain diagnostic files under
`fastEmbedR-results/candidate-smoke`. A pending four-GPU smoke is a
resource gate, not a successful validation. Never overwrite the stable
image while jobs still use it.

## UCT HPC image naming and storage

Benchmark-worker changes that do not change the installed R package or its
dependencies do **not** require rebuilding the SIF. The float32 timing-worker
correction in the 2026-11-07 matched CPU cohort uses the existing package
commit `535d071` image. Keep that image unchanged while its CPU arrays or
L40S pilot are queued or running.

For the next package release, use the existing stable HPC filename
`/scratch/firenze/NN/singularity/fastembedr_cuda.sif`. Build to a temporary
file **inside a compute allocation**, verify package and dependency identities
there, then replace the stable file atomically only after every queued,
running and held job that could read the previous bytes has ended. Never
overwrite a SIF under an active job. Record the package commit, image SHA256,
and benchmark-script hash in each cohort manifest. Check a large image digest
on a compute node, never the head node. A job must refuse to start if its
expected package or image identity differs. Keep old images only while a live
job needs them or their retention is explicitly required; audit references
before any cleanup. This uses one stable **deployed** filename while retaining
source identity and fail-closed reproducibility.
