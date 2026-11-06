# Bounded two-A10G 10,000-row qualification, 3 November 2026

This job compares one versus two CUDA GPUs for file-backed 3D UMAP and
2D t-SNE on the same generated 10,000-row, 30-neighbor ring graph. It is
a scaling and numerical diagnostic, not a real-dataset manuscript result.
The run uses 20 UMAP epochs and 15 t-SNE iterations, saves finite-output
and per-GPU work evidence, and compares paired layouts. Each GPU case has
a 120-second timeout and must verify no residual GPU context before the
next case. Any failed case stops the bundle.

The source is fastEmbedR commit
`4571fe483e29a528b4b837b5c9f5cefe509fac7b` plus the current
isolated-candidate tracked diff. The patch applied cleanly to a fresh
local clone; its reconstructed diff matched the candidate SHA256
`fdd118576d2f5811fe5483c1215f4f974add81edf8eb09963cbd984573d71f42`.
Source style and shell/R syntax checks passed.

| Artifact | SHA256 |
| --- | --- |
| `candidate.patch.xz` | `968a7b9e14e460daaf94c771e9b85d11b6d41ea003a0baea054a9def342aaa4f` |
| `tests.tar.xz` | `92f83b570cd4b2bc3ce6c85809be4334fba7bcd9d21ce55c20d5c125f5ac5f7d` |
| `run.sh` | `8eed13c5659c48d12ad24543b2b364cf628fa637e1ae04e8e8357377b678826c` |

The prior authorized two-A10G jobs consumed at most about 6.6 GPU-job
minutes (about US$0.33 at the published US$3/hour rate). A 15-minute
server timeout for this job adds at most US$0.75 at that rate, leaving
the combined upper bound below the user's US$2 cap. Actual billing may
vary; no later GPU job is authorized by this calculation.

The UCT HPC GPU pause remains in force. The original Mac panel remains
suspended. This job does not use either machine.

Submitted at 2026-11-03 13:27 UTC as
`tkcaccia/6ae9e1530e0338d1bb7f3f03`, URL
<https://huggingface.co/jobs/tkcaccia/6ae9e1530e0338d1bb7f3f03>.
The Jobs API reported `SCHEDULING` at submission. No case result is
claimed until the job reaches a terminal state and its logs are audited.

## Terminal audit

The job reached `ERROR` at 2026-11-03 13:54:09 UTC. Its
83-line [terminal log](terminal.log) records both A10G UUIDs, successful
NCCL all-reduce and all-gather, and all 20 epochs of the 10,000-row
single-GPU UMAP fit. The first case then failed the runner's physical-GPU
identity assertion, as predicted by the preflight review. The runner stopped
immediately; no two-GPU optimizer or t-SNE case started. `CASE_FAIL` follows
the runner's bounded `check_cleanup` call, so the owned GPU-context check
passed before exit. The Jobs API reported a terminal error and then listed
no active jobs. The numerical output of the failed case is not accepted as
a qualification result.

After submission, a source review found that explicit one-GPU optimizer
plans omitted the physical GPU UUID from result and checkpoint metadata.
The isolated package candidate now records that UUID for both file-backed
UMAP and t-SNE. The submitted job uses the earlier immutable patch and may
stop at the first one-GPU metadata assertion. Its outcome must be recorded
before preparing any revised qualification job.
