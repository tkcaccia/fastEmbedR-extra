# Expected fastEmbedR capability contract

Draft requirement, 2 November 2026. This is the intended product contract,
not a claim that the current release satisfies every combination.

## Methods and outputs

| Method | Required result | Full fit | Landmark fit |
| --- | --- | --- | --- |
| PCA | Scores and loadings, with at least 2 or 3 components on request | Fit the basis on all rows and produce a score for every row | Fit the basis on a declared subset, then project every row |
| t-SNE | A finite 2D or 3D coordinate for every row | Optimize every row | Optimize declared landmarks, then place the remaining rows without moving the fitted reference unless explicitly requested |
| UMAP | A finite 2D or 3D coordinate for every row | Optimize every row | Optimize declared landmarks, then transform every remaining row |
| Louvain | A community label for every row | Cluster the full graph | Cluster a declared landmark graph, then assign every remaining row |
| Leiden | A community label for every row | Cluster the full graph | Cluster a declared landmark graph, then assign every remaining row |

The package must also expose nearest-neighbor graph construction and
reuse, because t-SNE, UMAP, and graph clustering depend on it. Graph
construction, fitting, projection, transformation, and assignment are
separate stages in the result metadata and benchmarks.

## Execution modes

Every method above must have the following public, selectable routes:

| Backend | Required device modes |
| --- | --- |
| CPU | One worker and more than one effective worker on one machine |
| CUDA | One GPU and coordinated work on at least two GPUs |
| Metal | One Apple GPU |

Here, multiple CPUs means multiple effective CPU workers on one machine,
and multiple GPUs means multiple GPUs in one job. Distributed execution
across several nodes is a separate requirement.

Each route must accept a resident input and an SSD backed input. A
landmark route must be available with either input mode. The requested
combination must execute on the stated backend or fail clearly; it must
never silently switch backend, reduce the requested worker or device
count, replace a full fit with landmarks, or replace SSD processing with
an unreported resident copy. A stage may use fewer workers for a stated
algorithmic reason only when the effective count is reported and the
route is not presented as accelerated by those idle workers.
An explicit unsupported error is safer than a hidden fallback, but the
combination remains an unmet requirement until it executes and passes
its qualification tests.

“SSD backed” means the input and the dominant intermediate state needed
for the declared scale can exceed RAM or VRAM under an enforced memory
budget. The result must identify which of these are on disk or resident:
input, neighbor index, graph or affinities, coordinates or scores,
optimizer state, and labels. Streaming only the input does not qualify
the whole workflow as SSD backed when a graph or optimizer state still
requires the full data in RAM or VRAM. Disk space and write volume must
also be budgeted. SSD runs are conducted outside the UCT HPC under the
current site policy.

“Landmark” means a declared, reproducible subset and a distinct
approximation. The result must record the selected original row IDs or
a deterministic rule that reproduces them, the number of fitted rows,
the assignment or transform method, and whether fitted rows moved.
Landmark PCA, t-SNE, UMAP, Louvain, and Leiden must each return one
result per original input row. Their quality is compared with a full
fit on the same rows and evaluation sample; landmark output is never
described as a full fit.

## Result and benchmark evidence

Each call returns a machine-readable record of the requested and actual
backend, device IDs, effective workers by stage, precision, dimensions,
storage mode by stage, full or landmark mode, row count, source identity,
seed, parameters, timings, peak RAM and per-device VRAM, disk peak and
bytes written, output path, and artifact hashes. A failed stage leaves
a failure record and resumable checkpoint where the method supports one.

Qualification requires all requested rows to be present and finite,
with source and output hashes verified. On fixed seeds and paired inputs,
report a quality comparison against appropriate exact or established
references, sampled nearest-neighbor recall where KNN is used, and
stability across seeds. Report the fitting and downstream transform or
assignment times separately. A speed claim needs a quality-qualified
CPU comparator and the same timing scope; a GPU device must show positive
work and allocation on that device. For multi-GPU claims, every requested
GPU must have measured work. For multi-CPU claims, report effective
parallel work and scaling against one worker. Claims about memory
capacity must compare measured peak use with the input and intermediate
sizes, not infer capacity from a successful run alone.

“Fast” is evaluated on prespecified datasets and timing scopes. The
target is for multicore CPU to improve useful large-case throughput and
for Metal and CUDA to beat the fastest quality-qualified CPU route on
representative large cases. Small cases may lose to device setup costs;
those losses remain in the table. A speed ratio without passing quality
and, where applicable, neighbor-recall gates is descriptive only.

The benchmark should cover all five methods and all available backends
on the same named datasets, with explicit pass, fail, unsupported, and
not-run statuses for every route. UMAP and t-SNE need both 2D and 3D
checks. CPU and CUDA need one-device and multiple-device scaling on
representative small and large cases. The Mac campaign must report every
dataset, including quality failures; the 100M Deep1B case is a separate
full-row SSD study. HPC comparisons use resident memory only and remain
subject to the separate GPU authorization policy.

## Implementation gaps in the source-locked Mac candidate v3

The inspected package archive has SHA-256
`ae37cd4f3638ec59d515456e5c6e0c1bf6d38de8fba05414aab471a0abd76e00`.
The following gaps are source-visible. This is not a complete test of
every combination in the target contract.

| Area | Existing route | Missing work for the target contract |
| --- | --- | --- |
| PCA landmarks | Resident `pca()` accepts `xtest`; full out-of-core PCA exists on CPU, CUDA, and Metal. Isolated candidate adds `massive_project_pca()` after streamed landmark fitting; CPU and single-CUDA correctness and checkpoint recovery passed on Chiamaka | Metal and multi-GPU projection and recovery need real validation and a full performance campaign. Out-of-core `pca(xtest=)` still explicitly fails |
| Full graph t-SNE | File-backed affinities stream on CPU and CUDA | No full-graph Metal SSD route; CUDA full graph requires 2D; CPU coordinates and update state stay in RAM, CUDA coordinates stay in VRAM |
| Landmark t-SNE | CPU, CUDA, and Metal landmark paths exist | Metal landmark projection rejects 3D; complete route matrix and quality evidence remain to be established |
| Full graph UMAP | CPU, CUDA, and 2D Metal graph routes exist; the isolated CUDA candidate exposes public synchronized CPU updates and an MNIST70k 1/2/4/8-worker pilot passed with identical outputs | Metal full graph rejects 3D; Metal retains the full layout in unified memory; coordinated CUDA keeps a full layout on each GPU; multi-dataset scaling evidence remains needed |
| Landmark UMAP | CPU, CUDA, and Metal landmark paths exist | CUDA and Metal 3D landmark refinement explicitly fail |
| Full graph Louvain and Leiden | CPU file-backed graph route and CUDA cuGraph/Dask route exist. The isolated candidate adds parallel independent restarts for resident CPU graphs; an MNIST70k 1/2/4/8-worker pilot passed | File-backed CPU optimizer still accepts one coordinator; no full-graph Metal route; CUDA requires a distributed resident graph rather than SSD streaming |
| Landmark Louvain and Leiden | CPU, Metal, and single CUDA device routes exist. The isolated candidate now routes independent CPU fitting restarts through the automatic resident and file-backed landmark workflows; small real-CPU consistency tests passed | Landmark clustering does not offer coordinated multi-GPU fitting; whole-workflow CPU scaling and the full backend and storage matrix lack qualifying evidence |

Multi-GPU PCA, t-SNE, UMAP, Louvain, and Leiden source paths exist, but
their presence is not a performance or quality qualification. The Mac
panel currently measures CPU and Metal PCA, t-SNE, and UMAP on 11 named
datasets. Its separate 100M Deep1B queue measures a narrower set of
full-row SSD routes. It does not fill the missing implementation cells.
UCT HPC GPU work remains paused under its separate authorization rule.

A later isolated CUDA candidate extends resident landmark UMAP projection
and fixed-reference refinement to 3D. It compiled for Chiamaka's `sm_120`
GPU, but its device test remains pending because a Bora calculation owns
the GPU. The source-locked Mac panel and published package do not contain
this candidate, and no 3D landmark performance claim is established.
