# Hugging Face two-A10G qualification, 3 November 2026

Job `tkcaccia/6ae986550e0338d1bb7ef9bf` completed at
2026-11-03 07:04:40 UTC with `CURRENT_CANDIDATE_TWO_GPU_PASS`.
The Hugging Face Jobs API reported `COMPLETED` and then no running jobs.
This followed the documented image setup failure and same-image CPU preflight
in `../SETUP_INCIDENT_20261103.md`.

## Exact build and hardware

- Image: `rapidsai/base:25.06a-cuda12.8-py3.12`
- Source base commit: `4571fe483e29a528b4b837b5c9f5cefe509fac7b`
- Source patch SHA256: `b45bf0aaba50036c0b079d5a60a66b78117e40ca49ffb3f7216ab2964bb75cce`
- Test bundle SHA256: `e8406cefead57f9e3b0a5fb16108ece75959b181ab0817de9ac91c16ebc5c89e`
- Runner SHA256: `281c503aadc943e3b752033d5a725f9afd5b17055ce8c83aff9002a514173391`
- Installed `fastEmbedR.so` SHA256: `1d960482713a38060c49587111d7a9d9a8247164716a55df63f2a5987572d61f`
- GPU 0: NVIDIA A10G, `GPU-44b16be0-e376-cc27-dfc7-b9aa4c37fef4`
- GPU 1: NVIDIA A10G, `GPU-71f1adf4-b408-e316-f963-f1474ea911f4`
- NVIDIA driver: 580.178.04; CUDA build target: `sm_86`

The job verified archive hashes, installed the package, and asserted two
CUDA devices, native CUDA KNN, and NCCL availability. Every bounded case
passed, with a GPU-context cleanup check after each case.

| Case | Scope of passed check |
| --- | --- |
| NCCL all-reduce and all-gather | Two GPUs; zero out-of-bounds numerical results |
| KNN | Exact two-GPU KNN on a 32-row reference case |
| UMAP | File-backed full-graph 3D, 1,024 rows, two-GPU synchronized CUDA/NCCL route |
| t-SNE | File-backed full-graph 2D, 1,024 rows, coordinated two-GPU route |
| PCA | File-backed covariance fit, 10,000 × 64, 5,000 fit rows per GPU |
| Landmark PCA projection | 1,000 fitted landmarks projected to 10,000 rows on two GPUs; maximum absolute error 1.264e-6 |
| Louvain and Leiden | Two-GPU graph clustering, 1,024 rows; zero mixed or disconnected communities in the checked graph |
| 3D landmark t-SNE | Resident CUDA fit and held-out projection on one allocated GPU; separate single-GPU check |

The full 138-line `job.log` is preserved here (SHA256
`d9f54702f808a793a3d51125a1a4afbeef97ca92a8e0cad7f9b198ca8e62be4c`).
The five CSV files were reconstructed from its `RESULT_FILE` blocks; every
reconstructed file matched the SHA256 printed by the remote job.

This qualifies small device and pipeline correctness only. It is not a
performance benchmark, a large-data result, a 3D multi-GPU t-SNE result,
or evidence for UCT HPC hardware. The candidate remains unmerged. The
Hugging Face timeout was 30 minutes. Both GPU jobs were terminal and the
second completed after about five minutes; the exact account charge has
not been checked, but published per-minute billing and job durations place
the work below the user-approved US$2 total cap.
