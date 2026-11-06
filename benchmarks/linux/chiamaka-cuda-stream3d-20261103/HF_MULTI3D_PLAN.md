# Prepared two-GPU development validation

The input bundle is staged locally at
`/tmp/fastembedr_hf_multi3d_20261103` for a two-A10G Hugging Face job.
The server timeout is 30 minutes. Automatic approval review blocked
submission because the uncommitted package patch would be exported to
Hugging Face. Explicit approval for that transfer is pending.
Hugging Face lists `a10g-largex2` Jobs at US$3/hour, so a full
30-minute run is approximately US$1.50 under the requested additional
US$2 cap (https://huggingface.co/docs/hub/jobs-pricing).

| Input | SHA256 |
| --- | --- |
| `candidate_final.patch.xz` | `fac95898faf6ff2aef0a6dabbcca662e86b90632bfeb2d2620cd3544ea7e8afd` |
| `tests_next.tar.xz` | `1c52603ef382eaa3f4afeb95ad81f7e946db7d15ea94c78d9fabc678e04fc53b` |
| `hf_run_multi3d.sh` | `ddeeaae520a37f9e6e43581639e4762c058ca1e9e8df44dc63f6004bb8e11afb` |
| `hf_validate_multi3d.R` | `6c688effef2d3944188a5d3983b579547d990eadb0bfb1fd8ba02091fb7fb9da` |

The runner checks input hashes; reconstructs the exact package candidate
against commit `4571fe483e29a528b4b837b5c9f5cefe509fac7b`; builds
CUDA and NCCL; checks both GPU identities; runs two-device NCCL
all-reduce/all-gather; then runs resident 2D and 3D t-SNE, resident 2D
and 3D UMAP, resident multi-GPU PCA, and a separate file-backed 3D t-SNE checkpoint/resume
development test. Each case has a
two-minute timeout and a GPU-context cleanup check. The file-backed
case runs on Hugging Face only. It must never be copied into an HPC
benchmark or submitted to the UCT HPC.

Local preflight passed: reconstructed patch applies without whitespace
errors, the R test parses, and the shell runner parses. These checks
do not establish GPU correctness.

## Updated bundle with resident graph clustering

The newer bundle supersedes the inputs above for the next permitted job.
It includes all earlier checks plus resident two-GPU Louvain and Leiden
independent-restart tests. The source reconstruction was compared byte for
byte with the isolated candidate, excluding Git metadata. The validation
R script parses and the runner passes shell syntax checks.

| Input | SHA256 |
| --- | --- |
| `/tmp/fastembedr_hf_multi3d_20261103/candidate_next.patch.xz` | `41fe22b7b4bff380914b9e86707d703fc162f14090668173d4ddafd9c91f005c` |
| `/tmp/fastembedr_hf_multi3d_20261103/tests_with_cluster.tar.xz` | `858cd40c6bd5dc4ffe335ef6f318d7563d934a8b21e440f845fe37f8e2fea386` |
| `/tmp/fastembedr_hf_multi3d_20261103/run_with_cluster.sh` | `4b6907fd4a53046e2ec81f0a7f1cf1713d5514b6479f4796f0295e2a2dc924af` |
| embedded `hf_validate_multi3d.R` | `27bbc0c34f428e4c8a3037a6c8e9ab2b00740b2a8c012604371450ebb8ff2b3c` |

This older bundle is superseded. It must not run on the UCT HPC, where
GPU tests are paused and file-backed work is forbidden.

## Coordinated graph fit bundle

The current bundle replaces independent clustering restarts with one
host-synchronized partition across two GPUs. Its graph fixture crosses
device row boundaries and checks per-device work, communication, modularity,
and connectivity. It also retains resident t-SNE, UMAP, PCA, NCCL, and a
separate Hugging Face-only file-backed development check.

| Input | SHA256 |
| --- | --- |
| `candidate_coord.patch.xz` | `b41694cf24c60d44e3a2f780509d5b17ab2c11d774257eb97e2356fe87e4d9f8` |
| `tests_coord.tar.xz` | `598b6090c25acda161fd08e4c2ad0db3566b041e35ffcce978c5bba7adbd763b` |
| `run_coord.sh` | `247916ee656203f765c741818c7588e72e404b4df4792e56a33ac8a5ed9a6649` |

The patch applies to the recorded base commit and reconstructs the
candidate byte for byte, excluding Git metadata. R and shell parsing
passed. The complete candidate built with CUDA on Chiamaka, and focused
R API checks passed; actual two-GPU qualification is still pending.

The current revision adds CPU coordinated-fit controls and exercises
consensus inside the two-GPU clustering case:

| Input | SHA256 |
| --- | --- |
| `candidate_coord_v2.patch.xz` | `6e49604df8567e887ed70995ec3d21b75cd79e47978c705ea9d37fde3cc3500a` |
| `tests_coord_v2.tar.xz` | `684855bc7938fb4a8e887d93a977fce404dfb674b39ce9a1f182520a3303618c` |
| `run_coord_v2.sh` | `e67fda6266abacb06f9d8f4c317bbfc3f73c7c93dec01ce816b095263a9c8653` |

Use this revision after source export is approved. The patch applies and
reconstructs the candidate byte for byte. The package built with CUDA,
and focused CPU/API tests passed. No two-GPU correctness claim follows
from those checks.

The latest source revision is `candidate_coord_v3.patch.xz`
(`1cd030b6ab8a82262ec81cd20070af29113141c11f731e3c9027c4f2064d9fc8`).
It pairs with `tests_coord_v2.tar.xz` above and `run_coord_v3.sh`
(`83c337fdf29f5f6489b88d4f59318ccfdf31a68c7f2090c80a07c16ff77888dd`).
The previous source bundle is superseded. The latest patch reconstructs
the candidate byte for byte and passes whitespace and shell checks.
