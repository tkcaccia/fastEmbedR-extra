# Standalone CUDA UMAP initializer: deterministic graph rows

Observed on Chiamaka's RTX 5060 Ti on 3 November 2026. The isolated
candidate was compiled with strict CUDA in the existing Singularity image,
without a GPU binding during installation. Source archive SHA256:
`a61c5e3d519f04f0f5c18a7a680c9d6ef863a0b6bd3cbd4d9d3f516f028094db`.
Installed shared-library SHA256:
`32f63beffde96354aa95c8e451d42b49ed2ee139d31c5205e79a5cad0df586bf`.

The original implementation produced a maximum 0.01394 coordinate
difference when initializing twice from the same fixed 48-row KNN input.
Its GPU graph dump also yielded different edge sets on repeated calls.
The corrected standalone path computes a row-capacity bound from the KNN
indices, checks for overflow, and sorts each GPU graph row before spectral
diffusion. It errors if a row would need more than 256 slots.

Bounded idle-only tests of the corrected build passed:

- 48-row 3D: finite output, nonzero third-axis variation, exact repeatability.
- 48-row 2D: finite output and repeatability regression.
- 1,024-row 3D: finite output and exact repeatability; first call took
  0.275 seconds in this isolated test.

Each test ended with no CUDA compute context. Logs in this folder contain
the build and per-case outputs. These checks do not qualify the general
resident CUDA UMAP graph builder, which still uses the unsorted fixed-width
path, or establish large-dataset performance. Prepared CUDA 3D UMAP
optimization remains unsupported.
