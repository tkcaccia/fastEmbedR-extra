# Bounded two-A10G candidate device checks, 4 November 2026

The [final Hugging Face job](https://huggingface.co/jobs/tkcaccia/6aead89bc78863f9c632357f)
completed on two NVIDIA A10G GPUs. It tested an **isolated, uncommitted**
fastEmbedR candidate, not the released package or the UCT HPC image.
The job used a 20-minute server timeout and finished in under four minutes.
The earlier [first attempt](https://huggingface.co/jobs/tkcaccia/6aead5530e0338d1bb7f8e51)
stopped before execution because one shell argument was too long. The
[second attempt](https://huggingface.co/jobs/tkcaccia/6aead5eb0e0338d1bb7f8e81)
passed the embedding and PCA checks, then exposed an Rcpp metadata type
error in resident clustering. Casting the effective GPU worker count to
`int` resolved that failure in the final candidate.

The final job checked the base source commit
`4571fe483e29a528b4b837b5c9f5cefe509fac7b` and verified these
local artifacts before building:

| Artifact | SHA-256 |
| --- | --- |
| `candidate.patch.xz` | `f5be1ad8b49cb5d60e164823a4bde6a2d3bf129d29debf5a012cf6a1cb4f159a` |
| `tests.tar.xz` | `422160861c1713e72862039f29cc4a21468741b4d84387cc136fc96c25ddc2ae` |
| `run.sh` | `b73b1a397a8fae914bac2d15f7a7dfd62392ab51ded5c0d48c4660c6c9189e6e` |
| Installed `fastEmbedR.so` | `aef9756e80f619cf87f167c0633c3f745ae6db771b161be0cfb9d69110bbed5f` |

The two visible GPUs had UUIDs
`GPU-1b84e136-2f1a-e871-da92-d9378e33c3db` and
`GPU-ebf91a66-df66-85af-34f4-01d1099c2133`. The driver was
`580.178.04`. NCCL all-reduce and all-gather both passed.

| Case | Observed result |
| --- | --- |
| Resident 2D t-SNE | Two-GPU versus one-GPU maximum coordinate difference `4.66e-10`; 192 attraction edges on each GPU. |
| Resident 3D t-SNE | Maximum difference `2.92e-05`; 192 attraction edges on each GPU. |
| Resident 2D/3D UMAP | Finite layouts and 1,920 edge visits on each GPU in each case. |
| Resident PCA | Maximum score difference from the projected matrix `7.61e-07`. |
| Resident landmark PCA | All-row difference `5.47e-07`; external test-row difference `1.67e-07`; both projections reported both CUDA devices. |
| Resident Louvain and Leiden | Both produced two connected communities with modularity `0.5` on the fixed eight-vertex graph. |
| File-backed full-graph 3D t-SNE | On a 17-row, 102-edge graph, two-GPU versus one-GPU maximum difference `2.15e-04`; interrupted checkpoint/resume difference `8.72e-05`. |

The complete [terminal log](terminal.log) records the source, build,
device identities, individual cases, and final
`CUDA_TWO_GPU_DEVELOPMENT_CHECK_PASS` marker. [validate.R](validate.R)
and [run.sh](run.sh) are the exact submitted scripts. The runner checks
for released GPU contexts after every case.

These are small device correctness checks. They do not establish
manuscript-dataset embedding quality, scaling, memory capacity, or a
multi-GPU speed advantage. File-backed testing ran on Hugging Face,
outside the UCT HPC, under the user's explicit bounded approval.
