# Matched-settings Mac/HPC resident cohort

This versioned HPC worker uses the same scientific settings as the running
Mac CPU/Metal panel: float32 input digests verified in HPC job 1592295,
CPU rank-30 (or input-width-minus-one) PCA preprocessing for UMAP/t-SNE/
clustering, 30 neighbors, t-SNE perplexity 30 with 300 normal iterations,
and the same seed and 600-row quality sample. PCA fits original features.
Preprocessing, graph construction, target-method fit, quality and writing
are timed separately. All inputs and algorithm state remain resident in
memory. File-backed input and GPU exposure are rejected before execution.

The new-image COIL20 four-core 2D UMAP pilot 1593561 completed. It reported
rank 30, fit 0.339 s, trustworthiness 0.9735 and label accuracy 0.8917.
The corresponding Mac source-locked four-core case reported fit 0.153 s,
trustworthiness 0.9755 and accuracy 0.8917. These single-run observations
qualify the matched route; they are not publication speed estimates.

Array 1593945 contains the remaining 21 two- and three-dimensional UMAP
cases at four cores across all 11 datasets, throttled to one active case.
`cases.jsonl` records the exact pilot and array plans. Four COIL20 method pilots in array 1593960 completed for PCA, t-SNE,
Leiden and Louvain. The matched 21-case 2D/3D t-SNE wave 1594037 was
accepted. The first attempt to submit the 30-case PCA/Leiden/Louvain wave
hit `AssocMaxSubmitJobLimit`. On 2026-11-06, the first five tasks were
submitted as array `1601087` (`--array=0-4%1`). All five completed with
Slurm exit `0:0`, completed provenance, CPU backend identity, finite
quality summaries and nonempty output RDS files. Slurm gives each array
task a distinct `SLURM_JOB_ID`, which is recorded in its provenance.
The remaining tasks 5-29 were then submitted as array `1601111`
(`--array=5-29%1`). It was active at the last check and is not yet an
audited result set.
All 77 seed-4, four-core matched cases are in `cases.jsonl`. Other seeds,
core counts and GPU backends still need matched cohorts. The earlier
HPC raw-input waves remain separate development evidence and must not be
combined with this cohort in the manuscript.

## Matched CPU scaling expansion

`plan_scaling.py` expands the 77 source-locked four-core, seed-4 cases to
1, 2, 8, 16 and 32 cores: 385 additional cases with the same input
digests, methods, dimensions, preprocessing, quality checks and resident
storage contract. It rejects changed storage mode, spill, multiple fits,
missing dataset/method coverage, and unqualified routes before writing a
new plan. The generated array scripts allocate only CPUs on Ada and
point to the same reviewed matched worker and package image. Every array
element invokes one case; the default 77-element array can be overridden
with a quota-friendly subset.

Three focused planner tests and shell syntax checks for all five generated
array scripts passed locally. A generated planning fixture has 77 cases
per new core count and `cases.jsonl` SHA-256
`19db9d72321ab61f208d6fe53cf44435c52f35f1b366e1b59b71cb53afbbe114`.
The generated plan was deployed at
`/scratch/firenze/NN/benchmarks/matched_scaling_afeaffc_20261106`.
COIL20 Leiden pilots `1604055`, `1604062`–`1604065` completed at 1, 2,
8, 16 and 32 requested cores. All used the CPU backend, returned 1,440
labels and the same ARI 0.6675, 16 communities and modularity 0.9036.
Fit seconds were 0.014, 0.049, 0.201, 0.440 and 1.301 respectively;
this small graph is dominated by threading overhead. These are single
development fits, not scaling estimates for the manuscript.

COIL20 2D UMAP pilots `1604066`–`1604070` used the same core counts
and a 15-minute allocation cap. The 1- and 2-core cases completed with
CPU backend identity, trustworthiness 0.9789 and 0.9738, label accuracy
0.8933 and 0.8900, and fit times 0.915 and 0.378 seconds respectively.
The 8-, 16- and 32-core cases failed closed in the benchmark worker
because the release package reports fewer effective UMAP workers than
requested. The release's R and C++ UMAP paths cap worker counts at four.
Preserve the failures and do not represent the high-core runs as
qualified scaling results. An isolated package candidate under
`/media/user/Lion/ChatGPT/fastEmbedR/in-progress/multicpu-umap-20261106`
raises the configured limit to
32 and makes native stage worker counts grow with problem size. R parse,
C++ syntax, package build and focused embedding tests passed, followed
by the MNIST cases below. Peak RAM, repeatability and broader quality
remain unqualified, so it must not be used for a manuscript result yet.

### Isolated CPU UMAP candidate check

The package candidate was built on an Ada compute node in job `1604085`
from source archive SHA-256
`244112c726c6ba9ba676721d58943aa1eb56285b769515bd1a568dd0e617cd92`.
The focused installed-package embedding tests passed in job `1604091`.
An initial MNIST pilot `1604095` failed before science when the container
selected its release library; a second attempt `1604102` loaded that
release library in the worker and failed the expected worker-count gate.
Both failures and their logs remain in HPC scratch. The versioned v3
worker checks the candidate library path before loading the package;
its SHA-256 is
`76d65c360994f59272500fb8b541e8e554a4ca6f11a7035d9c589b431f93fb11`.

Five resident, full 70,000-row MNIST 2D UMAP cases completed with this
worker and the same input, rank-30 preprocessing, seed and quality
sampling. The results are single-run development evidence:

| Requested CPU cores | Job | Fit seconds | Trustworthiness | Label accuracy |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 1604107 | 24.005 | 0.9418 | 0.9733 |
| 4 | 1604108 | 10.176 | 0.9399 | 0.9750 |
| 8 | 1604105 | 5.740 | 0.9413 | 0.9767 |
| 16 | 1604109 | 4.613 | 0.9325 | 0.9717 |
| 32 | 1604110 | 4.409 | 0.9410 | 0.9750 |

Each case recorded CPU backend identity, a finite all-row output, an
allocation ID and completed provenance. The 16-core trustworthiness
decrease needs repeated-seed evaluation. The source-locked release
image is used only as the R/C++ toolchain; the v3 worker checks and
loads the separately built candidate package.

The versioned v4 runner (SHA-256
`d1cf3f582ee12916a9369a8fb0c0966665b14b04547453a3c3978d2c2ed27900`)
records the R child process's peak resident memory and CPU time from
Linux `getrusage`. Its 1-, 16- and 32-core MNIST repeats completed as
jobs `1604115`–`1604117`. Peak R-process RSS was 1,804,012,
1,804,984 and 1,805,536 KiB; fit seconds were 25.186, 5.330 and
2.913. All three retained CPU backend identity, completed provenance
and nonempty all-row outputs. Trustworthiness was 0.9418, 0.9381 and
0.9380; label accuracy was 0.9733, 0.9750 and 0.9717. These peak
values cover the R child process, not the whole Slurm allocation.

The same seed produced different 16- and 32-core quality values across
the v3 and v4 runs. The threaded optimizer therefore needs a paired
repeatability and quality audit before any manuscript speedup or
quality claim. These runs demonstrate a route beyond the release's
four-worker cap, but they do not prove linear scaling or a final
quality gate.

Two additional seeds (17 and 42) completed at 1, 16 and 32 cores in
jobs `1604123`–`1604128` using the same v4 worker. Across seeds 4, 17
and 42, mean fit time was 23.863, 4.518 and 3.329 seconds respectively;
mean trustworthiness was 0.9394, 0.9381 and 0.9384. Mean label accuracy
was 0.9733, 0.9717 and 0.9728. Peak R-process RSS stayed between
1,804,012 and 1,805,996 KiB across these nine runs. This gives a
development-level 7.17-fold mean fit speedup from 1 to 32 requested
cores on MNIST, with no large mean quality loss in this three-seed
sample. The optimizer's concurrent atomic updates still make individual
same-seed results nondeterministic. Repeatability and other datasets
must be checked before formal claims or package integration.

### Isolated multi-CPU 3D UMAP candidate

The earlier Fashion-MNIST pilot showed that 3D UMAP's optimizer was
serial even when 32 CPU cores were requested: seed-4 fit time was
28.073 seconds at one core and 22.855 seconds at 32 cores. An isolated
candidate extends the native 2D atomic optimizer to the third
coordinate. Its source archive SHA-256 is
`3bcb6e364259e3d3781b332e8df98dea342b6a4ae796b49791bfc65dc506029f`.
Compute-node package build and focused 2D/3D checks passed in job
`1604162`; the resident embedding regression file passed in `1604166`.

Matched resident Fashion-MNIST 3D fits on all 70,000 rows used seeds
4, 17 and 42. The new candidate's mean fit time was 29.364 seconds
at one core and 4.105 seconds at 32 cores (jobs `1604169`, `1604170`,
`1604173`, `1604174`, `1604176`, `1604177`). The prior serial 32-core
path averaged 28.217 seconds (jobs `1604148`, `1604175`, `1604178`).
Mean trustworthiness was 0.9811 at one core, 0.9808 for parallel
32-core and 0.9811 for serial 32-core; mean label accuracy was 0.7322,
0.7289 and 0.7289 respectively. Peak R-process RSS stayed near
1,805,000 KiB. The paired 2D regression cases `1604171` and
`1604172` also completed with trustworthiness 0.9726 and 0.9731.

This is a development result on one real dataset, not a formal JSS
comparison. Atomic updates permit same-seed variation, and other
datasets, output quality gates, CPU scaling efficiency and memory
behavior still require qualification before merging the candidate.

The same 3D candidate then passed full 70,000-row MNIST cases at one
and 32 cores for seeds 4, 17 and 42 (jobs `1604184`–`1604189`). Mean
fit time was 28.316 versus 4.065 seconds, a 6.97-fold ratio; mean
trustworthiness was 0.9459 versus 0.9443, and mean label accuracy
0.9728 versus 0.9722. All six cases had CPU backend identity, finite
all-row output, completed provenance and R-process peak RSS around
1,805,000 KiB. Resident embedding, UMAP initialization and
supplied-KNN regression files passed in job `1604191`; unavailable
GPU-specific tests were skipped on this CPU node. These two datasets
support further integration work, but do not cover the eleven-dataset
matrix or establish publication-scale variability.
