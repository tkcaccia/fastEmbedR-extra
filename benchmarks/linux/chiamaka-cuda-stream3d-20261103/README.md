# Single-GPU CUDA file-backed 3D t-SNE candidate

This isolated candidate extends streamed full-graph t-SNE to a three-column
initial layout on one CUDA GPU. Directed CSR affinity chunks remain bounded;
layout, gradients, gains and updates remain resident on the GPU. It reuses
the existing cubic-grid 3D cuFFT repulsion kernels, adds a directed 3D
attraction kernel, and makes initial upload, checkpoint state and final
output dimension-aware. The coordinated 3D path still rejects explicitly;
the existing NCCL offsets and reduction counts support 2D only.

The source is the local isolated `in-progress/metal-landmark-3d-20261102`
candidate. Chiamaka built it in the existing 29 October Singularity image
with CUDA and NCCL enabled. The tested installation is
`/tmp/fastembedr_cuda_stream3d_20261103/library`; its `fastEmbedR.so`
SHA256 is
`69bd70a2884c628ca5baaaac2a8dc8d4a6da19c137f106bc49a08dfcd2577e49`.
The native source SHA256 values are:

- `src/massive_matrix.cpp`:
  `669663e6d75eb74ea3be97cfbc5f09e74ce759f2c6ec1175ab6156506d61c624`
- `src/embedding_cuda_kernels.cpp`:
  `57ae6ae2ef40cf90381980d80211fdc0047f68d536f9e279d160a3d6ef7f2c17`
- `src/massive_tsne_cuda.h`:
  `e8f56f1252270ab7d2f4b0ee9a224cd9ef534823a0cdc670e1465696acc04f33`

Before this device-kernel change, a 32-row file-backed CUDA 2D test
interrupted at iteration 2, resumed, and finished with finite coordinates
and a removed checkpoint sidecar. The later 3D attempt was refused by the
idle admission check because Bora was active. No GPU calculation started
in that attempt.

The final validation queue runs `check_cuda_checkpoint_3d.R` and then
`check_cuda_checkpoint_2d.R`, each with a 120-second limit and a separate
GPU release check. It waits up to 12 hours for 30 continuous idle seconds
without Bora or another GPU compute context. Its PID was `40849` when
verified live on Chiamaka; the log is
`/tmp/fastembedr_cuda_stream3d_20261103/queue.log`. All image, library,
native source and test-script checksums had passed, and no test had started.
The queue script is `run_when_idle.sh`, SHA256
`4d2ae1d709d663b2e078531a12b63cf53c8f4afaf02c68156f0f73764c7bc5e9`.

## Terminal audit and corrected retry

The original idle-only queue admitted the GPU at 17:54:50 UTC. Its first
case stopped before optimizer execution with `CUDA t-SNE requires 2D`.
The container had resolved `/opt/r46/lib/R/library/fastEmbedR`, its older
image copy, despite the launcher setting `R_LIBS`. The original
[`queue.log`](queue.log) and
[`cuda_checkpoint_3d.log`](cuda_checkpoint_3d.log) are preserved.

Both test scripts were corrected to prepend the verified build library
with `.libPaths()` before loading fastEmbedR. The corrected scripts and
[`run_when_idle_retry.sh`](run_when_idle_retry.sh) passed syntax, parse,
package-path, and checksum preflight. The retry kept the same idle-only
Bora/GPU-context gate and wrote separate logs. It admitted the GPU at
17:59:28 UTC. The 32-row 3D checkpoint/resume case passed at 17:59:32,
and the 2D regression passed at 17:59:34. The runner verified zero GPU
compute contexts after each case and ended with status 0 and
`ALL_3D_AND_2D_TESTS_PASSED`. See the complete
[`queue_retry.log`](queue_retry.log),
[`3D log`](retry_cuda_checkpoint_3d.log), and
[`2D log`](retry_cuda_checkpoint_2d.log). Local copies match Chiamaka
SHA256 exactly. The final layouts are finite and the checkpoint sidecars
were removed after successful resume.

This validates a small one-GPU device case and a 2D regression. It does
not validate large-data quality, performance, or coordinated 3D CUDA.
This development check ran on Chiamaka, not on the HPC; it is not a
formal file-backed benchmark or a manuscript speed result.

The subsequent coordinated 3D and resident multi-GPU developments are
recorded separately in [MULTIGPU.md](MULTIGPU.md),
[RESIDENT.md](RESIDENT.md), and
[UMAP_RESIDENT.md](UMAP_RESIDENT.md). Their two-GPU device checks remain
pending.
