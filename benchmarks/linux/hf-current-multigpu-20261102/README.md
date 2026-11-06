# Current-candidate Hugging Face two-GPU qualification

Prepared 2 November, refreshed and submitted 3 November 2026.
The submitted job is `tkcaccia/6ae9852e0e0338d1bb7ef8df`; see
[submission record](SUBMISSION_20261103.md). The proposed run uses Hugging
Face Jobs `a10g-largex2` in the provider-selected region with a 30-minute
server timeout. At the published $3/hour rate, 30 billed minutes are $1.50;
startup time may add cost, so the requested ceiling is $2.00. The launcher
must be cancelled if that ceiling cannot be maintained.
Pricing source: <https://huggingface.co/docs/hub/jobs-pricing>.

The Docker image is `rapidsai/base:25.06a-cuda12.8-py3.12`. The source base
is fastEmbedR commit `4571fe483e29a528b4b837b5c9f5cefe509fac7b` plus
`candidate.patch.xz` SHA256
`b45bf0aaba50036c0b079d5a60a66b78117e40ca49ffb3f7216ab2964bb75cce`.
The patch is the exact tracked diff in the isolated
`in-progress/cuda-graph-options-20261102` checkout. Dependencies are
faissR commit `7a22de471eb6d83dd9d1873ef0f89401ea8f11f5` and gpuinfo
commit `a1122acf1cdf59c2fb2e19283353f3231d85bde3`.

The test bundle `tests.tar.xz` has SHA256
`e8406cefead57f9e3b0a5fb16108ece75959b181ab0817de9ac91c16ebc5c89e`.
The job runner `run.sh` has SHA256
`281c503aadc943e3b752033d5a725f9afd5b17055ce8c83aff9002a514173391`.
The two-GPU KNN preflight was corrected from a stale four-device assertion.
The new fifth R script checks full-row, file-backed landmark PCA projection
on both GPUs with checked model and landmark identities. `run.sh` checks both
archive hashes, clones pinned source, applies
the patch, installs R 4.6.1 and dependencies, and compiles for A10G `sm_86`
with cuVS and NCCL. It first runs pinned `nccl-tests` all-reduce and
all-gather across both devices with numerical checks, then checks two-GPU
KNN, UMAP, t-SNE, full PCA, landmark PCA projection, Louvain, and Leiden
with explicit CUDA backends. Each case has a two-minute timeout
and a GPU-context cleanup check. Cases stop at the first failure. The job
log prints source and binary identities, case results, and output CSVs.
The final case checks 3D CUDA landmark t-SNE fitting and held-out model
projection on one of the two allocated devices; it is a separate resident
kernel check, not a multi-GPU t-SNE claim.

Local preflight passed: the patch applied to a fresh clone of the pinned
base, recreated the candidate's exact Git diff (SHA256
`03b51d77a3b2be62082bdd35436efe34842b9edf5bf867b550802717be119ed8`),
passed source style and `git diff --check`, and built an R source archive.
The patch also contains CPU parallel clustering restarts, separately
validated on Chiamaka. It now includes the automatic resident and
file-backed landmark CPU restart routing, also tested on Chiamaka, and
the CUDA 3D landmark UMAP and t-SNE candidates. Both compiled for
`sm_120` on Chiamaka. The isolated single-GPU 3D landmark t-SNE and UMAP
correctness cases, plus 2D regressions, passed on 3 November; see
`../chiamaka-cuda-tsne3d-20261102/evidence-20261103/README.md`. The source
patch now includes the corrected landmark-coordinate assertion, which ignores
non-numerical R matrix attributes. This
cloud bundle does not test 3D landmark UMAP or claim CPU scaling.
Shell syntax and all six R validation scripts parse. The local preflight
cannot prove remote image
package resolution, GPU behavior, or job lifecycle.

No UCT HPC GPU work is authorized by this job. The active Mac benchmark is
source-locked and separate. Results will remain provisional until the job
reaches a terminal status and its logs and outputs are audited.

## Submission status

Submitted at 2026-11-03 06:54:38 UTC to Hugging Face Jobs as
`tkcaccia/6ae9852e0e0338d1bb7ef8df`, with `a10g-largex2` and a
30-minute server timeout. The user explicitly approved a US$2 maximum.
At the current US$3/hour rate, the 30-minute runtime ceiling is US$1.50.
At the first inspection, the job was `SCHEDULING` and pulling its image.
No test result is claimed until the job reaches a terminal state and its
logs are audited.

The first submitted job failed during unpacking because the image lacks the
`xz` executable. A short CPU job in the same image confirmed Python 3.12
with `lzma`, Git, Mamba, and tar. The runner now uses Python `lzma` for the
two controlled archives. The first two-GPU job is terminal; no algorithm
case started. See [setup incident](SETUP_INCIDENT_20261103.md).

## Audited retry result

The bounded retry `tkcaccia/6ae986550e0338d1bb7ef9bf` reached
`COMPLETED` at 07:04:40 UTC. Its 138-line log contains the final
`CURRENT_CANDIDATE_TWO_GPU_PASS` marker and all nine case passes. The
reconstructed CSV result tables match the checksums printed in the job.
See [evidence-20261103](evidence-20261103/README.md) for exact build and
device identities, methods, sizes, numerical checks, and limitations.
A subsequent Jobs listing found no running jobs. This is a correctness
qualification, not a publication performance benchmark.
