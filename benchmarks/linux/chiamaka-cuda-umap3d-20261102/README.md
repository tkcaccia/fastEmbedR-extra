# CUDA 3D landmark UMAP candidate, 2 November 2026

Scope: one RTX 5060 Ti on Chiamaka, using the existing 29 October
Singularity image and an isolated temporary R library. No UCT HPC job.
The candidate extends the native CUDA landmark affine projection and
fixed-reference refinement kernels from two dimensions to two or three.
The public 3D rejection is removed only for CUDA; Metal is unchanged.

Admission: verify source archive and image SHA256, device UUID, and that no
unrelated compute context is present. Build CUDA with architecture 120.
Run the focused 3D CUDA UMAP test with a 90-second limit. It checks finite
3D coordinates, nondegenerate third dimension, fixed landmark positions,
CUDA refinement metadata, and held-out model projection. After terminal
exit, verify owned descendants and GPU context release. Only if it passes
and cleanup is clear, run one bounded 2D CUDA landmark regression case.
Stop on the first failure or uncertain cleanup. Preserve logs and hashes;
do not reset the GPU or alter active jobs or images.

Current state: source archive SHA256
`86e55db0268472eecc013ca07e884d8a854e86ea84de33261ed663d8d026ae4d`.
Chiamaka verified the transferred archive with the same hash. A CUDA build
without GPU device binding completed at 20:31:01 UTC in the temporary
library. The log reports CUDA compiled, architecture 120, and package
installation DONE. Installed shared-library SHA256:
`368e7006da5c407e251bd6aa1a9b540900fdde2ad04276a1a220d629ad613a36`.
The preserved `build.log` SHA256 is
`155774a1e737e46c76a1cd7b5ca6d84c85a68baa1c071b6cff667e5d538ab67b`.

The GPU test has **not started**. Chiamaka's GPU showed a Bora Python
compute context before the build and still showed one afterward. No Bora
process, GPU context, image, or job was altered. Runtime correctness,
quality, and 2D regression remain unverified for this candidate.

The two test scripts are staged in the same temporary directory and their
remote hashes match local copies: `validate_umap3d.R`
`1704c6d2137c6255e253a420ba4713de9e5a9d7d91974581ebe035a67f218382`
and `regress_2d.R`
`809250f5c13bf3d45b20718725a0e02483f28e4be972a8f9fc9ff35212bdaea3`.
Both parsed locally. They will run only after an idle-device admission check.

With GPU binding disabled, the exact installed build passed the existing
`test-landmarks.R` CPU file at 20:37:45 UTC. Its saved log SHA256 is
`175ebc73cbcbcec25c43df89f783ca1898999b7ecd758848201ab9ff4d907deb`.
This validates shared R landmark behavior but provides no evidence that the
new 3D CUDA kernels run correctly.

An attempted 3D device-test launch at about 20:35 UTC stopped at its
idle-device admission check (exit 42) before starting a container. A new
Bora Python compute context had appeared. No CUDA test or cleanup sequence
was started for that rejected admission.
