# Bounded two-A10G MNIST quality check, 4 November 2026

The [Hugging Face job](https://huggingface.co/jobs/tkcaccia/6aeadd15c78863f9c6323761)
completed at 07:25:57 UTC using an isolated, uncommitted fastEmbedR
candidate. It used two NVIDIA A10G GPUs. The package and test bundle
passed their SHA-256 checks before installation. Source patch SHA-256:
`f5be1ad8b49cb5d60e164823a4bde6a2d3bf129d29debf5a012cf6a1cb4f159a`.
Installed library SHA-256:
`b52285beabea835ce04a6cef7ff255d2112ec7233b1e87b04ac0c3eeb6ce14ba`.
The source patch is retained in the sibling `hf-multi3d-20261104` folder.

The job downloaded the official [MNIST NumPy archive](https://www.tensorflow.org/tutorials/load_data/numpy)
directly, without exporting local dataset files. Its SHA-256 was
`731c5ac602752760c8e48fbffcf8c3b850d9dc2a2aedcf2cc48468fc17b673d1`.
It selected 30 training images from each digit with NumPy seed 42, producing
a 300-row, 784-feature float32 matrix normalized to [0, 1]. The selected
matrix and labels had SHA-256 values `d53369fbfa15613c9613d1f6884001ee234710003b4a7aaf7754803ecf24b545`
and `c073b6f2be13594f791b5e437de43994885522bf76d7bda17d95622b7ae0ad97`.

Each embedding used seed 42. t-SNE used perplexity 15, 50 PCA dimensions,
50 early-exaggeration and 250 main iterations. UMAP used 30 neighbors.
Trustworthiness and exact high-/low-dimensional neighbor preservation
were scored at 15 neighbors on the full 300-row sample. Label accuracy is
majority-vote accuracy from 15 embedded neighbors.

| Method | Backend | Trustworthiness | Preserve@15 | Label accuracy |
| --- | --- | ---: | ---: | ---: |
| t-SNE 2D | CPU | 0.92875 | 0.58533 | 0.70333 |
| t-SNE 2D | 1 CUDA | 0.92692 | 0.57156 | 0.63667 |
| t-SNE 2D | 2 CUDA | 0.92581 | 0.57089 | 0.65000 |
| t-SNE 3D | CPU | 0.94916 | 0.62267 | 0.74667 |
| t-SNE 3D | 1 CUDA | 0.94962 | 0.62600 | 0.75333 |
| t-SNE 3D | 2 CUDA | 0.94717 | 0.62244 | 0.72333 |
| UMAP 2D | CPU | 0.90888 | 0.52733 | 0.70667 |
| UMAP 2D | 1 CUDA | 0.91112 | 0.53511 | 0.71000 |
| UMAP 2D | 2 CUDA | 0.90745 | 0.52244 | 0.71333 |
| UMAP 3D | CPU | 0.92369 | 0.55844 | 0.70333 |
| UMAP 3D | 1 CUDA | 0.92844 | 0.56422 | 0.71667 |
| UMAP 3D | 2 CUDA | 0.92353 | 0.56067 | 0.71000 |

The largest two-GPU trustworthiness decline from CPU was 0.00295
(2D t-SNE). The 2D t-SNE label accuracy was 0.05333 lower on two GPUs
than on CPU; that difference needs larger, repeated data checks.

Clustering used one CPU-built, 20-neighbor SNN graph for all fits. Every
partition passed the connected-community audit. ARI compares communities
with the ten digit labels.

| Method | Backend | ARI | Modularity | Communities |
| --- | --- | ---: | ---: | ---: |
| Louvain | CPU | 0.33509 | 0.61223 | 8 |
| Louvain | 1 CUDA | 0.30091 | 0.61031 | 8 |
| Louvain | 2 CUDA | 0.30091 | 0.61031 | 8 |
| Leiden | CPU | 0.34455 | 0.61593 | 8 |
| Leiden | 1 CUDA | 0.33716 | 0.61585 | 8 |
| Leiden | 2 CUDA | 0.33716 | 0.61585 | 8 |

The run also repeated the small two-GPU device checks for resident PCA,
landmark PCA, 2D/3D t-SNE and UMAP, resident clustering, and file-backed
3D t-SNE outside the UCT HPC. The complete log is `terminal.log`, the exact
runner is `run.sh`, and the quality script is `validate_mnist.R`. The exact
submitted script and shared metric functions are in `tests.tar.xz`.
No UCT HPC job was submitted.

This is a **small, single-seed quality check**. It does not establish
publication-scale quality, speed, memory efficiency, multi-GPU speedup,
Metal quality, or file-backed capacity. The larger named-dataset panel,
landmark comparison, and Mac device qualification remain outstanding.
