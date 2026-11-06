# Resident multi-GPU CUDA PCA development check

The isolated package candidate at
`fastEmbedR/in-progress/cuda-multigpu-3d-20261103` now accepts an in-memory
double matrix for experimental two-to-four-GPU covariance PCA through the
public `pca(..., backend = "cuda", devices = ...)` API. CUDA devices split
both covariance and score projection by row. The small symmetric
eigendecomposition runs on CPU. This algorithm route performs no file-backed
matrix reads or writes. It is distinct from out-of-core PCA.

Chiamaka compiled the candidate with CUDA and NCCL enabled in
`/tmp/fastembedr_pca_resident_20261103`; `R CMD INSTALL` returned 0. The
final installed native library SHA256 is
`d80915174b96997586cc1bd6e0bb60cd15fb403772a1d5503c40b619929b3886`.
Strict installed-package dispatch tests passed 12 PCA, 11 UMAP, 9 t-SNE,
and 38 CUDA device-identity assertions. One idle-gated GPU numerical control
passed covariance and score projection against R reference calculations
for a 64-row, 16-column matrix against the final rebuild. Bora was untouched,
and no compute context remained after the control. `single_gpu.log` and
`single_gpu_exit` preserve this control; `check_single_gpu.R` and
`run_single_gpu.sh` preserve its exact procedure.

The one-GPU control exercises the native PCA worker but **does not validate
two-device coordination or performance**. The public two-to-four-GPU route
needs the prepared Hugging Face or another authorized two-GPU check. The UCT
HPC GPU campaign remains paused, and no HPC job was submitted.
