# CUDA graph-option candidate, 2 November 2026

Latest package GitHub base: `4571fe483e29a528b4b837b5c9f5cefe509fac7b`.
Isolated package checkout: `in-progress/cuda-graph-options-20261102`.
The original `umap` checkout and active Mac panel were not changed.

The candidate adds native CUDA Louvain/Leiden support for the newly added
vector consensus, projection weighting, and `small_groups` options. Each
partition and the final clustering use the existing native CUDA kernels.
Canonical graph construction, consensus edge agreement, exact double-precision
projection weighting, and nearest-core assignment run in host C++/R. Their
execution is identified in result metadata. This is a hybrid route; GPU
acceleration and competitiveness on realistic graphs remain unmeasured.

Chiamaka candidate directory:
`/mnt/sata_ssd/fastEmbedR/in-progress/cuda-graph-options-20261102`.
CUDA-enabled package build in its `validation-lib` completed successfully
using the existing 29 October image. The graph-option and graph-clustering
test files passed with CUDA hidden. After Chiamaka's previously occupied GPU
became idle, both files passed on its RTX 5060 Ti. The combined
consensus -> projection -> CUDA clustering -> small-group route passed.
Each GPU test had a 90-second limit, strict test failure status, and no
remaining compute context after completion. Logs are in the candidate
directory: `build-v2.log`, `test-cpu-masked-v4.log`,
`test-clustering-cpu-masked.log`, `test-cuda-options-v3.log`, and
`test-cuda-clustering-v1.log`.

`Rscript tools/check_source_style.R` and `git diff --check` passed locally.
The code is uncommitted and has not been pushed. Next: benchmark CPU versus
CUDA on real graphs at increasing sizes, audit memory and quality, then
decide whether the hybrid option stages need GPU kernels. Multi-GPU
clustering and 100M Deep1B remain separate validation work. UCT HPC GPU
is still paused; no HPC GPU job was submitted.

Current local package diff SHA256:
`da1b9d9392f1ee703aa0e410e836eea78b9db8b56f24e38329f4ebd43ea7b60f`.

## README package links

The source archive excludes `docs/` through `.Rbuildignore` but retains
`README.md`. Relative README links to eleven documentation files therefore
failed package URI checks. In the isolated checkout, these links now use
GitHub `main` documentation URLs through Markdown reference definitions.
All eleven target files are tracked in the package repository. A new source
archive contains the README and no `docs/` folder; CommonMark resolves twelve
documentation links and finds zero relative `docs/` links. R 4.6.1 package
structure and CRAN incoming checks on that archive did not report the original
file URI warning. The limited checks still reported unrelated faissR/vignette
and checkbashisms warnings. The README fix remains uncommitted with the CUDA
candidate.

## Real MNIST70k pilot

The versioned pilot under
`benchmarks/linux/graph-options-cuda-20261102/evidence/` uses the existing
70,000-row, 15-neighbor MNIST KNN cache and aligned 2D PCA layout on
Chiamaka. It runs Leiden with four consensus partitions, projection weighting,
and nearest-core assignment. Inputs are resident in memory. Input SHA256:
KNN `0651d481a290cb41de4888b5288aab008ac91d971066a372f5fd1e5584e61e1a`;
layout `3b51aecbd4d69334f5da67d3e13b22dda3a93d19f6bc444a4894f93ec9647689`.
The initial CPU v1 failed admission because the log occupied the required
empty output directory; no calculation ran. CPU v2/v3 and CUDA v1/v2 completed
successfully with separate six-minute limits. No compute context remained
after either CUDA case. The package binary SHA256 for these runs is
`7d3503cc7a57556a18ece91f37fd2794b0466de9857204eccf502274d715307b`.

| Case | Fit seconds | Total wall seconds | Host peak RSS | Label ARI | Raw modularity | Unassigned |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU v2 | 2.739 | 5.23 | 479 MB | 0.3670 | 0.976501 | 6 |
| CPU v3 | 2.752 | 5.22 | 479 MB | 0.3670 | 0.976501 | 6 |
| CUDA v1 | 2.275 | 4.99 | 618 MB | 0.3538 | 0.975619 | 3 |
| CUDA v2 | 2.278 | 4.97 | 618 MB | 0.3587 | 0.975811 | 6 |

The two CPU runs were identical in membership, reweighted graph, and
unassigned rows. Same-seed CUDA runs differed in all three; membership ARI
between CUDA repeats was 0.775. GPU partitions and CPU partitions likewise
had ARI around 0.77. The CUDA route is therefore not bitwise repeatable at
this size. Final modularity is NA whenever nearest-core assignment leaves
unassigned rows; raw modularity is preserved separately. The pilot has too
few repetitions, one dataset, and no VRAM measurement to support a general
speed or quality claim. The ~1.2x fit-time ratio is provisional.

The candidate now reports `repeatability = "not_bitwise_deterministic"`
from its native CUDA clustering bridge. A CUDA-enabled rebuild completed;
new binary SHA256 is
`5802a679ae9f837f36230780c2ba98aa91f438d4c8d9890edba8c23c9c63cf37`.
The focused CUDA graph-options test passed against this rebuild, and no GPU
compute context remained. The real MNIST pilot above used the preceding
binary; it was not silently reclassified as a result from the rebuild.

The same script was then run for Louvain on the rebuilt binary, with two CPU
and two CUDA repetitions. Its input hashes and graph settings match the
Leiden pilot. All four cases completed and both CUDA cases left no compute
context:

| Case | Fit seconds | Total wall seconds | Host peak RSS | Label ARI | Raw modularity | Unassigned |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU v1 | 0.937 | 3.39 | 476 MB | 0.3559 | 0.975830 | 11 |
| CPU v2 | 0.938 | 3.44 | 475 MB | 0.3559 | 0.975830 | 11 |
| CUDA v1 | 0.607 | 3.32 | 615 MB | 0.3594 | 0.974459 | 4 |
| CUDA v2 | 0.601 | 3.27 | 616 MB | 0.3594 | 0.974459 | 4 |

Both Louvain repeats matched exactly within each backend. CPU-versus-CUDA
membership ARI was 0.748. The CUDA fit-time ratio is about 1.55x, while total
run time is close because of input and container overhead. This does not
remove the Leiden repeatability limitation or prove a general GPU advantage.

## CUDA Leiden refinement race follow-up

Source inspection found that the CUDA refinement proposal checked whether
the source community was a singleton, then the concurrent apply kernel checked
the mutable community count again while other threads changed it. The second
check was removed in an isolated candidate. The proposal check still uses the
stable pre-apply snapshot. The CUDA-enabled rebuild passed the graph-clustering
and graph-option tests, including connectivity, on Chiamaka. New binary SHA256:
`188eedbff9cca00e2627413996b84ed4b965b472d79522828a4eb6bcd87e8d9d`.

Five independent MNIST70k Leiden CUDA runs with the same seed and inputs
(v3-v7 in the evidence directory) now match exactly in final and raw
membership, reweighted graph, and unresolved row IDs. Their raw modularity is
0.9765112, fitted time 2.269-2.291 seconds, total wall time 4.94-5.00 seconds,
and host peak RSS about 619 MB. The earlier pre-fix CUDA v1-v2 differed with
ARI 0.775. This is strong evidence that the mutable refinement guard caused
the observed variation on this case. It does not prove bitwise determinism on
other graphs or GPU architectures; the API retains its conservative
repeatability metadata pending broader validation.
