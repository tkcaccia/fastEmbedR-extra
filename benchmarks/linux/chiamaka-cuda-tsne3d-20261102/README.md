# CUDA 3D resident landmark t-SNE qualification

Scope: one RTX 5060 Ti on Chiamaka, using the existing 29 October image,
an isolated source archive, and an isolated temporary R library. No UCT
HPC job or SSD streaming is involved. The code extends the device-resident
landmark t-SNE projection from two to two or three output dimensions. It
uses the existing dimension-templated affine and fixed-reference kernels.

Source archive SHA256:
`5d0bee0b0951c07d0d3b504c17716016938d401dd23ce35739b8652a613c48c0`.
The archive copied to Chiamaka matched this hash. The build used
`FASTEMBEDR_USE_CUDA=1`, `FASTEMBEDR_REQUIRE_CUDA=1`, and
`FASTEMBEDR_CUDA_ARCH=120` in the existing Singularity image without GPU
device binding. Installation completed with CUDA compiled. Installed
shared-library SHA256:
`c0d50292330cad4cd835394e5889b8b806e79d458d9b0beaecd2757421ef2839`.
The preserved `build.log` SHA256 is
`69127cd20273b10cfad0b2925338601920d29675319b34924db5beb7399c6e37`.

The exact installed build passed a CPU-only 3D landmark fit and held-out
model projection, with no GPU binding. The validation script SHA256 is
`25cde21261861e487a90eb0b69f7d46efcf6fa0dd60a8b45f0825ddccd7433da`;
the preserved `cpu-3d.log` SHA256 is
`c68346fa2f95324dc37db03c605d061b033c03c0afe992597b5e57e2463dcc6d`.
This validates the high-level dimension handling, not the CUDA kernels.

The two bounded test scripts are staged in the same temporary directory
on Chiamaka. Remote and local hashes match:

- `validate_3d.R`:
  `a6cc5330aa00944f673a3180ae211a4958914172e19dfe09a57bab28d4ebf037`
- `regress_2d.R`:
  `7b78471a451f3d26daae48149c96bf7d5c1f35ebae84766c5cb15e2767662692`

At 20:47 UTC, the assigned GPU UUID
`GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5` was occupied by Bora Python
PID 3529758. No device test was started. At that point, runtime correctness remained
unverified. The device test must require idle admission and a finite
runtime, preserve logs, and verify that all owned processes and GPU
contexts have ended. Only a successful 3D case with proven cleanup permits
the separate 2D regression case. Any failure stops the bundle.

An idle-only queue was started on Chiamaka at about 21:00 UTC as PID 3537120.
The queue script SHA256 is
`a264206d3e0d77a881e9cd119b7e65d46c9d22c211a5b5feb347e6382c33600c`.
At 21:01:06 UTC, this same process was live, all image/source/library/test
hashes had passed, and Bora PID 3534268 still occupied the GPU. The queue
had started no GPU test. It waits at most 12 hours and requires five
continuous idle minutes with no Bora compute process or GPU context.
Each test has a 120-second runtime limit, terminal process/context checks,
and fail-fast sequencing: 3D t-SNE, 3D UMAP, 2D t-SNE, 2D UMAP. The queue
log is `/tmp/fastembedr_cuda_tsne3d_20261102/logs/queue.log` on Chiamaka;
the terminal result is preserved in `evidence-20261103/`.

## Device result, 3 November 2026

The corrected bounded run finished at 06:48:07 UTC with all four CUDA cases
passing: 3D landmark t-SNE, 3D landmark UMAP in fuzzy and binary modes, and
2D t-SNE/UMAP regression. The 3D UMAP landmarks had zero coordinate
difference from their references; an earlier assertion failure compared
matrix attributes. The package candidate test now compares the coordinates
without their display attributes. The queue exited with status 0, and no
compute context remained. Exact scripts, checksums, logs, result tables, and
the earlier failure diagnosis are in [evidence-20261103](evidence-20261103/README.md).

These are small real-device correctness tests. They do not establish a
performance result or two-GPU support.
