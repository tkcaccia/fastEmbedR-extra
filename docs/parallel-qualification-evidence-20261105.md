# 5 November 2026 parallel qualification

The independent CPU/Metal fixed-graph Fashion-MNIST diagnostic completed on Silvano's Mac under `/Users/silvanopiazza/Documents/Stefano/fastEmbedR-metal-quality-20261105`. It used the isolated R 4.6 package build in `fastEmbedR-knn-audit-20261105/library`, the existing 5,000-row Fashion input, one shared CPU-created 30-neighbor graph and initialization, and 400 epochs. Seeds were 4, 17, and 42. The Metal result remained below the CPU silhouette by 0.0217 to 0.0353 across two Metal modes. This confirms the optimizer quality gap persists in the current candidate; it is not a passing quality gate. The raw log is `mac-fashion-quality.log`.

A separate four-L4 Hugging Face development job `6aeca76d0e0338d1bb808d2e` was submitted with an eight-minute server timeout and source archive SHA-256 `e2d15d87a58c0661fba3f7d45d5216af6e73a41fcc91e3526b9a4bc45ed5c415`. It tests four persistent CUDA clustering workers on four disconnected triangle communities, checks exact modularity 0.75, all four GPU identities, and post-worker compute-context cleanup. The source worker SHA-256 is `3ed88becdd4bf70dad3ba870d565994359ce0f3101bececd2fa4885fa6a06a62`. This is a small device qualification, not a physical over-VRAM or performance claim. Preserve its terminal result before considering a later case.

The job completed on 6 November. Its terminal log recorded four distinct
L4 UUIDs, four persistent GPU workers, all four devices used, four triangle
communities, exact modularity 0.75, and positive GPU memory allocation on
each device. The source-locked driver checked the 12 output labels and that
post-worker compute contexts equalled the initial baseline before printing
`FASTEMBEDR_FOUR_L4_V4_PASS`. The graph had only 12 vertices and 24
directed edges; it does not prove scaling or operation beyond combined GPU
memory. The archive was independently recovered from the job specification
and matched its recorded SHA-256.

UCT HPC GPU identity diagnostic job `1579109` is a separate, three-minute allocation-only check. It runs no scientific fit and reads Slurm allocation variables, `nvidia-smi` index/UUID/PCI identity, and compute contexts once on the allocated node. The earlier resident UMAP pilot `1570379` failed before child start because its index-to-UUID assumption was invalid; do not relaunch that source-locked pilot.

Diagnostic `1579109` completed with scheduler exit 0:0 and no compute
contexts. Slurm reported allocated host GPU indices `1,3`, while the
job's visible indices and `nvidia-smi` inventory were `0,1`. This
confirmed index remapping, so the old pilot's direct index lookup was
invalid. A new fail-closed launcher requires that the complete
`nvidia-smi` inventory exactly match the two CUDA-visible devices;
otherwise it refuses the run. Six local mapping tests passed, including
remapped, direct, ambiguous and duplicate cases. New launcher SHA-256:
`2fb5c0f0de994c271efe1c8ea2337ebfdb6ec900f0f90e43199c38905c575919`.
The new scheduler script SHA-256 is
`113fad24f676ba13253b3e881138523a6ba3d4759ba4c837a5e662728166c710`.

One corrected, source-locked, resident-memory L40S pilot `1587409`
completed on 6 November in 34 scheduler seconds with exit 0:0. The
allocated compute node verified the 8.5 GB image SHA-256
`144b878f42b8c10f2dc9bc3ee422c51caf5a090049c0f89027fdc27ad1f34773`;
the head node did not hash the image. The launcher mapped Slurm host
indices `0,2` to two visible UUIDs, ran a 160-row 3D resident landmark
UMAP fit using both L40S devices, checked 160 by 3 finite output and
unchanged landmark reference coordinates, then logged
`cleanup_verified` and `pilot_pass`. Its error file was empty.
This qualifies a small device and lifecycle route, not real-data quality,
multi-GPU speedup, or the manuscript campaign. No file-backed or streaming
scientific calculation ran on HPC.
