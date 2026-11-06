# Prepared CUDA 3D UMAP device check

Observed on Chiamaka's RTX 5060 Ti on 3 November 2026. The isolated
candidate was built with strict CUDA in the existing Singularity image.
Source archive SHA256:
`c464739900814982c31d790a5983993f58cd750f38752221b57a981c6131a406`.
Installed shared-library SHA256:
`76f67fb8ce43936925416666da79ddb6b15a9e5101003a0b24b86112f02c8991`.

The candidate reuses a 3D `umap_init()` layout through the existing CUDA
snapshot delta kernel. The 2D path remains on its previous optimizer mode.
The bounded, idle-only device check passed fuzzy and binary prepared graphs
on 48 rows: 3D output was finite, changed from initialization, and varied
along the third axis. The 2D prepared reuse regression also passed. The
test exited in under three seconds and left no GPU compute context.

`build.log` and `validate.log` contain the exact build and device outputs.
The subsequent documentation regeneration did not change compiled code.
This focused check does not establish larger-data speed or embedding quality.
