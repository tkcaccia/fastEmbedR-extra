# Versioned CUDA 10,000-row qualification after GPU-ID failure

The previous job `tkcaccia/6ae9e1530e0338d1bb7f3f03` stopped at the
first one-GPU UMAP result check after all 20 epochs. The package had
omitted the physical GPU UUID from explicit one-GPU optimizer plans.
The corrected isolated package records it in both UMAP and t-SNE plans,
results, and checkpoint parameters. A focused Mac R 4.6.1 test passed
31 assertions, including physical-device remapping changing a checkpoint
signature. This GPU job is a new versioned qualification, not a resume
of the failed job or its outputs.

The 10,000-row synthetic graph, 30-neighbor settings, two A10Gs,
per-case 120-second limit, cleanup gate, and 15-minute server limit are
unchanged. The runner fails the bundle on any case error or uncertain
GPU-context cleanup. It verifies NCCL, then compares one- and two-GPU
3D UMAP and 2D t-SNE calculations. This is a scaling and numerical
diagnostic, not a real-dataset manuscript benchmark.

Source base: fastEmbedR commit
`4571fe483e29a528b4b837b5c9f5cefe509fac7b`, plus the exact
isolated-candidate tracked diff. A fresh local reconstruction matched
the candidate files, and source style, shell syntax, and `git diff
--check` passed.

| Artifact | SHA256 |
| --- | --- |
| `candidate.patch.xz` | `be0213bd0e538ec4c73fd3dcd4fcd35f2eae594b5c91ee1eab095bae1fb8c5a5` |
| `tests.tar.xz` | `92f83b570cd4b2bc3ce6c85809be4334fba7bcd9d21ce55c20d5c125f5ac5f7d` |
| `run.sh` | `a926ae24fbd9751c35e20f75cefb730178b69fd196e519abc3010763f469485b` |

Two earlier GPU jobs used at most 6.6 billed minutes. The failed
10,000-row job and this version each have a 15-minute server limit.
At the published US$3/hour two-A10G rate, the conservative combined
upper bound is about US$1.83, below the user's US$2 cap. Hugging Face
states that Jobs are billed only while Starting or Running, not while
Scheduling; see <https://huggingface.co/docs/hub/jobs-pricing>.

The UCT HPC GPU pause remains in force. The original Mac benchmark
remains suspended. No result is claimed until this job is terminal and
its logs and cleanup are audited.

Submitted at 2026-11-03 14:00:11 UTC as
`tkcaccia/6ae9e8ebc78863f9c631cf40`:
<https://huggingface.co/jobs/tkcaccia/6ae9e8ebc78863f9c631cf40>.
The Jobs API reported `SCHEDULING` at submission.

## Terminal audit

The job reached `COMPLETED` at 2026-11-03 14:03:43 UTC. Its complete,
untruncated [145-line log](terminal.log) ends with
`CUDA_10K_TWO_GPU_QUALIFICATION_PASS`. Both NCCL checks, the four
optimizer cases, and the comparison case passed. The runner checked for
remaining GPU compute contexts after each case; all seven case-pass
markers follow that gate. The Jobs API subsequently listed no active jobs.

The assigned devices were two NVIDIA A10Gs with UUIDs
`GPU-8956f53f-770e-20cc-5fac-b9b3b09add14` and
`GPU-4319d2df-cb76-434f-9313-392ae92f87f0`. The native build had
cuVS, cuFFT, and NCCL enabled. Both algorithms produced finite 10,000-row
outputs, and their one- and two-GPU fits recorded the expected physical
UUIDs and positive per-device edge work.

| Method | One A10G | Two A10Gs | Two/one time | Layout comparison |
| --- | ---: | ---: | ---: | --- |
| 3D UMAP, 20 epochs | 1.597 s | 1.800 s | 1.127 | Exact coordinate match |
| 2D t-SNE, 15 iterations | 0.972 s | 1.737 s | 1.787 | Maximum difference 3.73e-9 |

All six saved CSV tables have SHA256 values
matching those printed in the job log. The two-GPU routes split edge work
evenly, but were slower at this small size because coordination overhead
outweighed the saved graph work. The ring graph is synthetic, and the
reported quality fields are diagnostic only; this run does not prove
real-dataset quality, large-data scaling, or a multi-GPU speed advantage.

After this immutable GPU job completed, the candidate was refined so that
the default CUDA t-SNE route does not acquire a new dependency on optional
`gpuinfo`; explicit device requests still record UUIDs. The updated focused
Mac test passed 34 assertions. This later source edit is not in this job's
recorded patch and needs its own CUDA qualification if used in a release.
