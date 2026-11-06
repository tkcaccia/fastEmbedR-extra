# Native 3D landmark gaps, 2 November 2026

This records source-confirmed implementation limits. A compiled path is not
runtime or performance evidence. The running Mac panel is source-locked;
its source and jobs must remain unchanged until it finishes.

| Route | Current evidence | Required next work |
| --- | --- | --- |
| CUDA resident landmark UMAP | Isolated 2D/3D kernels compiled for Chiamaka `sm_120`; runtime test queued behind Bora. | Verify finite 3D layout, fixed landmarks, held-out model projection, 2D regression, and terminal GPU cleanup. |
| CUDA resident landmark t-SNE | Isolated 2D/3D affine and transform kernels compiled for `sm_120`; shared CPU 3D fit and model projection passed. | Run the staged real-device 3D and 2D cases and verify cleanup. |
| Metal full UMAP and t-SNE fits | Native 3D fit tests exist in `test-umap-metal-3d.R` and `test-tsne-fft-3d.R`. | Audit their results on the M3 Ultra after the current panel completes; benchmark speed and quality separately. |
| Metal landmark UMAP | `R/umap.R` restricts Metal refinement to 2D; `embedding_metal_impl.mm` rejects 3D and its affine/refinement kernels address two coordinates. | Extend the native affine initializer and fixed-landmark refinement to 3D, keeping landmarks fixed. Compile and test on the Mac after the panel. |
| Metal landmark t-SNE | `transform_tsne_metal_impl` and `project_embedding_affine_metal_impl` reject 3D; the Metal transform kernel uses `float2`. | Add a native 3D fixed-reference transform and affine projection, then test 3D fit/model projection and 2D regression on the Mac. |
| CUDA file-backed full-graph t-SNE | `massive_tsne_optimizer.R` rejects CUDA 3D; `MassiveTsneCudaContext` allocates two-coordinate state and 2D FFT slabs. This also limits coordinated multi-GPU t-SNE to 2D. | Extend the full-graph CUDA FFT and coordinate state to 3D, with checkpoint, single-device, and two-device validation. This is separate from resident landmark t-SNE. |

For manuscript claims, distinguish full-fit dimensionality from landmark
projection and file-backed full-graph dimensionality. A 3D full fit does
not establish 3D support for the other routes. Metal and multi-GPU 3D
performance claims require real-device tests and audited timing/quality
results, not just successful compilation.
