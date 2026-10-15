# fastEmbedR Technical Manual

Companion implementation manual for the fastEmbedR software article. This
document describes the current package source, not an independent performance
claim. Function signatures and defaults are defined by the matching package
release; consult the installed R help for argument-level detail. A publication
archive must pair this manual with the exact package commit, source archive,
container digest, and benchmark-suite commit used for the final figures.
This is a pre-archive draft; the final source lock is still pending.

## 1. Architecture and status

The ordinary route accepts an in-memory matrix, selects or reuses nearest
neighbors, constructs a sparse graph, and optimizes a two- or three-dimensional
layout. PCA, t-SNE, UMAP, and community detection share the KNN and graph
layers where their objectives permit it. `backend = "cpu"`, `"metal"`, and
`"cuda"` are explicit requests; unsupported combinations error rather than
silently running on another backend. A GPU KNN stage followed by CPU graph
assembly is a mixed-stage workflow, not an entirely GPU computation.

The experimental massive-data route starts with a `massive_matrix()` descriptor
for a row-major float32 file. It separates (1) bounded input reads, (2)
file-backed KNN or posting lists, (3) a disk-backed graph, and (4) an optimizer
or landmark projection. The descriptor itself does not load the file. An R
matrix passed to `massive_matrix()` is already resident in RAM. A file-backed
input does **not** imply that every downstream state fits below RAM or VRAM:
coordinate arrays, optimizer state, CUDA reference shards, and caches have
separate budgets.

| Route | CPU | Metal | CUDA | Multi-device scope |
|---|---|---|---|---|
| Ordinary matrix PCA, UMAP, t-SNE | Native | Native | Native | Ordinary fits are single-device; file-backed PCA can partition fitting passes and score projection |
| File-backed PCA | Streamed covariance or wide sketch | Streamed covariance and score projection (up to 1024 columns) | Streamed covariance or wide sketch | CUDA can partition fitting and score rows across devices; Metal is single-device |
| Ordinary `graph_cluster()` | Louvain, Leiden, Walktrap | Louvain, Leiden | Louvain, Leiden | None in this API |
| File-backed KNN | Exact, faissR HNSW shards, coarse postings | Exact query/reference shards and exact landmark search | cuVS exact/IVF shards | CUDA query-row splitting and merged output |
| File-backed full UMAP | Streamed fuzzy CSR and optimizer | Streamed fuzzy CSR edges, mapped or resident host staging, one shared 2D Metal layout | Streamed edges, 2D/3D layout | Coordinated NCCL updates on CUDA; Metal is single-device |
| File-backed full t-SNE | Streamed affinities and FFT | Not implemented | Streamed affinities, 2D FFT | Coordinated 2-4 GPU 2D fit; global FFT on one GPU |
| File-backed communities | Louvain, Leiden, partitioned Walktrap | Landmark Leiden/Louvain with exact Metal KNN | Optional cuGraph Leiden/Louvain | 2-4 GPUs, resident distributed graph; no out-of-core GPU graph |
| Landmark projection | CPU | 2D UMAP interpolation and 2D t-SNE fixed-reference transform | CUDA | Query rows can be distributed on CUDA; this is not a multi-GPU full fit |

Multi-GPU paths are experimental. Correctness on synthetic or limited real
inputs must not be presented as evidence of speedup, lower aggregate VRAM, or
billion-row completion. The public methods expose `devices` only where their
implementation supports it. Full-graph Walktrap remains CPU-only. The cuGraph
Leiden/Louvain bridge passed a 1,024-row two-GPU synthetic test. A later
100,000-row two-/four-GPU test passed Louvain but exposed a cuGraph Leiden
reported-score discrepancy; larger and real-data validation remain open.

## 2. Public function map

The tables cover every export in the package `NAMESPACE`. Source paths below
are relative to the fastEmbedR package repository. `R/` functions orchestrate
native C++/CUDA/Metal implementations; they are not claims that all arithmetic
occurs in R. Each descriptor-returning function validates its inputs, and
bounded readers materialize only the requested rows.

### In-memory embeddings, reuse, and evaluation

| Function | Implementation and result | Source owner |
|---|---|---|
| `umap()` | One-call KNN, fuzzy graph, initialization, and layout; an explicit massive mode selects the experimental route. | `R/umap.R` |
| `umap_knn()` | Fits UMAP from a validated reusable KNN object; returns embedding and resolved parameters. | `R/fast_knn_umap.R` |
| `umap_init()` | Prepares reusable UMAP graph and initial coordinates. | `R/umap_init.R` |
| `prepare_umap_knn()` | Validates and prepares KNN input for the UMAP graph path. | `R/fast_knn_umap.R` |
| `tsne()` | One-call KNN, compact affinities, PCA/other initialization, FFT optimization, or explicit massive mode. | `R/fast_knn_tsne.R` |
| `tsne_knn()` | Fits t-SNE from a reusable KNN object and records sparse-affinity support. | `R/fast_knn_tsne.R` |
| `prepare_tsne_knn()` | Validates and prepares KNN input for the t-SNE affinity path. | `R/tsne_affinity_dispatch.R` |
| `pca()` | Blocked randomized SVD in memory, or streamed file-backed covariance/sketch route; returns scores, loadings, and metadata. | `R/embed.R`, `R/massive_pca.R` |
| `precompute_knn()` | Backend-dispatched all-neighbor search for later embedding or graph reuse. | `R/native_knn.R` |
| `precompute_query_knn()` | Searches a fixed reference for new/query rows without fitting a new reference layout. | `R/native_knn.R` |
| `select_landmarks()` | Selects a reusable in-memory landmark subset. | `R/landmark_model.R` |
| `project_landmark_model()` | Projects held-out/new rows from a fitted landmark reference. | `R/landmark_model.R` |
| `transform_tsne()` | Fixed-reference t-SNE transform; reference coordinates do not become an independent fit. | `R/transform_tsne.R` |
| `evaluate_embedding()` | Computes sampled neighborhood, distance, density, and optional label/batch diagnostics. | `R/evaluate_embedding.R` |
| `knn_graph()` | Converts KNN input into a compact undirected graph, with optional SNN weighting/pruning. | `R/graph.R` |
| `graph_cluster()` | Louvain, Leiden, or CPU-only Walktrap on an ordinary graph; returns assignments and diagnostics. | `R/graph.R` |

### File-backed inputs, search, and projection

| Function | Implementation and result | Source owner |
|---|---|---|
| `massive_matrix()` | Describes a `.f32` or `.fbin` source and records dimensions/file identity. | `R/massive_matrix.R` |
| `massive_read_rows()` | Reads a bounded consecutive row range into an R matrix for inspection. | `R/massive_matrix.R` |
| `massive_open_pca()` | Reopens a completed file-backed PCA manifest and score descriptor. | `R/massive_pca.R` |
| `massive_coarse_postings()` | Builds physical, center-assigned posting lists in streaming passes. | `R/massive_postings.R` |
| `massive_open_postings()` | Validates and reopens completed posting-list storage. | `R/massive_postings.R` |
| `massive_read_posting()` | Reads a bounded section of one posting list. | `R/massive_postings.R` |
| `massive_search_postings()` | Searches selected posting lists; omitted lists make this approximate. | `R/massive_postings.R` |
| `massive_posting_recall_pilot()` | Compares posting search against exact neighbors on sampled queries. | `R/massive_postings.R` |
| `massive_select_landmarks()` | Selects and writes landmark rows from a file-backed source. | `R/massive_landmarks.R` |
| `massive_landmark_knn()` | Writes query-to-landmark neighbor IDs and distances. | `R/massive_knn.R` |
| `massive_audit_landmark_knn()` | Audits sampled landmark-neighbor correctness. | `R/massive_knn.R` |
| `massive_read_knn_rows()` | Reads a bounded row range from file-backed KNN output. | `R/massive_knn.R` |
| `massive_full_knn_graph()` | Builds file-backed all-neighbor output by CPU exact/HNSW/postings, CUDA exact/IVF shards, or Metal exact shards. | `R/massive_knn.R` |
| `massive_project_landmarks()` | Projects rows to a fitted landmark layout, writing coordinates to disk. | `R/massive_projection.R` |
| `massive_open_projection()` | Reopens and checks a completed projection manifest. | `R/massive_projection.R` |

### File-backed graph and optimizers

| Function | Implementation and result | Source owner |
|---|---|---|
| `massive_knn_graph()` | Imports and validates a fixed-width KNN file pair without rebuilding neighbors. | `R/massive_graph.R` |
| `massive_umap_memberships()` | Computes directed UMAP memberships from KNN distances. | `R/massive_graph.R` |
| `massive_umap_fuzzy_graph()` | Externally symmetrizes memberships into fuzzy CSR. | `R/massive_graph.R` |
| `massive_fuzzy_graph()` | Reopens a validated fuzzy graph manifest. | `R/massive_graph.R` |
| `massive_affinity_graph()` | Reopens a validated t-SNE affinity graph manifest. | `R/massive_graph.R` |
| `massive_tsne_affinities()` | Computes conditional affinities and a normalized symmetric CSR graph. | `R/massive_graph.R` |
| `massive_tsne_optimize()` | Streams sparse attraction; applies CPU/CUDA FFT repulsion and checkpointable updates. | `R/massive_tsne_optimizer.R` |
| `massive_umap_optimize()` | Streams fuzzy edges for checkpointable CPU, Metal 2D, or CUDA epochs. | `R/massive_umap_optimizer.R` |
| `massive_weighted_graph()` | Imports fixed-width weighted edges for downstream graph processing. | `R/massive_graph.R` |
| `massive_csr_graph()` | Imports and validates a generic file-backed CSR graph. | `R/massive_graph.R` |
| `massive_read_graph_edges()` | Reads a bounded range of graph edges. | `R/massive_graph.R` |
| `massive_graph_partitions()` | Creates partition metadata for bounded graph processing. | `R/massive_graph.R` |
| `massive_read_graph_partition()` | Reads one bounded directed edge-list partition. | `R/massive_graph.R` |

### File-backed clustering

| Function | Implementation and result | Source owner |
|---|---|---|
| `massive_graph_modularity()` | Scans weighted graph edges to score supplied communities. | `R/massive_graph_modularity.R` |
| `massive_louvain_level()` | Performs one CPU file-backed Louvain level. | `R/massive_louvain_level.R` |
| `massive_leiden_refine_level()` | Refines one CPU Leiden level. | `R/massive_leiden.R` |
| `massive_leiden()` | Runs CPU multilevel Leiden with file-backed assignments. | `R/massive_leiden.R` |
| `massive_read_leiden_rows()` | Reads a bounded assignment range. | `R/massive_leiden.R` |
| `massive_louvain()` | Runs CPU multilevel Louvain with file-backed assignments. | `R/massive_louvain_level.R` |
| `massive_read_louvain_rows()` | Reads a bounded assignment range. | `R/massive_louvain_level.R` |
| `massive_walktrap()` | CPU partitioned Walktrap approximation, not exact global Walktrap. | `R/massive_walktrap.R` |
| `massive_read_walktrap_rows()` | Reads a bounded assignment range. | `R/massive_walktrap.R` |
| `massive_cluster_landmarks()` | Clusters landmark rows, then propagates assignments to source rows. | `R/massive_clustering.R` |
| `massive_cluster()` | Orchestrates in-memory, landmark, CPU full-graph, or optional multi-GPU cuGraph clustering as requested. | `R/massive_cluster_workflow.R` |
| `massive_read_cluster_rows()` | Reads a bounded range of propagated labels. | `R/massive_clustering.R` |

## 3. Nearest-neighbor implementation

For ordinary matrices, the CPU router uses exact search below 5,000 rows.
Larger Euclidean cases use compiled faissR HNSW through its C API; cosine and
correlation use the package's native HNSW route. Metal selects native exact or
IVF-Flat; CUDA selects cuVS brute force or IVF-Flat. The routing policy aims at
high recall, but the input distribution matters. A nominal 0.99 target is
**not** a measured 0.99 guarantee. In particular, Deep and Turing data with
similar shape can produce different recall. Always report the effective
algorithm and settings, rather than only the requested backend.

`massive_full_knn_graph()` instead processes query and reference blocks. CPU
`hnsw_sharded` builds a persistent faissR index for each reference shard,
searches the query blocks, then merges candidate distances and global IDs.
`hnsw_build` and `ef_search` can override faissR's shape-based policy for a
calibrated run. CUDA `ivf_sharded` uses cuVS inside each reference shard.
Metal `exact` searches a bounded float32 reference shard against bounded
query rows with the native Metal exact kernel, merging global IDs into the
same file-backed output. It rejects HNSW, IVF, and CUDA `devices` requests.
Metal currently reuploads the reference buffer for each query batch; this
is a correctness and bounded-memory route, not a persistent GPU index or
a demonstrated speedup. Metal uses unified memory, so the reported shared
buffer estimate is part of the host-memory budget, not independent VRAM.
The Metal landmark result reports dedicated `peak_vram_bytes` as unavailable,
not zero; `metal_buffer_bytes_estimate` describes shared allocations.
Exact sharded search scans all reference blocks and is primarily a correctness
baseline. `coarse_postings` scans selected physical lists. These routes do
not use NN-descent. Multiple GPUs split **query rows** and merge one KNN
output; that alone does not partition a single resident reference index
across GPUs. File-backed HNSW and IVF can make repeated input passes, so
storage I/O and index build must be measured separately from query time.
Each multi-GPU KNN result records `per_device$query_row_range` for the
assigned rows. IVF exact-neighbor holdouts exclude the first query batch
of every recorded range, which contains that worker's tuning pilot, and
reserve at least one held-out row per device.
The one-GPU sharded IVF graph records each reference shard's effective
`nlist`, `nprobe`, pilot count, and tuning attempts in `ivf_settings`.
The multi-GPU result retains those settings inside `per_device`.
`validate_multigpu_knn_matched.R` uses the same nonpilot query rows for
one- and two-GPU graphs and computes one streamed exact reference for both.
Its CSVs report per-row ID recall, effective settings, and elapsed time;
they do not prove all-row recall. The companion Linux wrapper
`measure_multigpu_knn_matched.py` samples process-tree RSS, process-attributed
VRAM by physical GPU UUID, and generated-payload disk allocation every
250 ms, with separate one-GPU and two-GPU phase records. Missing GPU
attribution fails the measurement instead of becoming zero VRAM. These
are sampled observations, not guaranteed instantaneous maxima; the
source input is excluded from generated-payload bytes. Every query row
is still part of the indexed reference, so "nonpilot" does not mean
held out of IVF reference construction.
When an exact-neighbor audit is requested, `per_device_audit` records
the sampled rows, mean and minimum ID recall, and rows below 0.99 for
every GPU. The audit fails if a device has no sampled rows or a sample
maps to multiple devices or none. Duplicate sample rows, nonfinite scores,
and recall values outside `[0, 1]` are rejected. This is sampled
validation, not a
guarantee of 0.99 recall on every query row.
`reference_replication_factor` and `minimum_reference_read_bytes` disclose
the per-worker reference scans; the latter is a lower bound, not measured
SSD traffic or evidence that reference buffers are shared across processes.
The multi-GPU full-KNN result reports `disk_budget_bytes` and
`payload_disk_bytes_before_cleanup`. After merging candidates, it records
their file identity when checkpointing is enabled and removes completed GPU
query shards before writing the final non-self graph. Peak KNN payload is
bounded by two candidate copies, `16n(k+1)` bytes, rather than two
candidate copies plus the final `8nk` bytes. The reported payload is the
larger of the measured shard-plus-merged and merged-plus-final file sizes;
it excludes the source matrix, metadata, and other workflow files.
The multi-GPU KNN coordinator and each worker capture source and reference
file identity before searching and reject changes during search or result
merge. This checks size and filesystem modification/status times; it is
not a full-content hash of the input matrix.
Before shard cleanup, a retained multi-GPU KNN merge is checked byte-for-byte
against its device shards. After cleanup, resume validates the retained
merged candidates against their checkpointed file identity. A modified
completed stage or committed partial prefix fails instead of being accepted
by size alone.

For multi-GPU CUDA `ivf_sharded`, a checkpoint commits only a completed
GPU query shard. An interrupted shard is discarded and searched again
from its first row with cuVS IVF-Flat; the coordinator can reuse other
completed shards after checking their output manifests and the source,
device UUIDs, settings, and implementation signature. This does not
persist or resume an IVF index partway through a shard. Single-GPU
`sharded_ivf` checkpointing remains unsupported, and no backend or
algorithm fallback is used. The coarse restart avoids treating a newly
built approximate index as identical to an interrupted one.

The Metal file-backed entry points are `massive_full_knn_graph(x, k,
output, backend = "metal", method = "exact")` and
`umap()`/`tsne()` with `massive = "landmark"`, `backend = "metal"`, a
file-backed `massive_matrix()` input, and a new `.f32` output. The full
KNN route accepts at most 127 non-self neighbors (the native kernel also
searches self); the landmark route accepts at most 128 neighbors and
16,384 input columns. Landmark UMAP requires `refinement_epochs = 0L`;
landmark t-SNE requires a 2D output. Both use `n.cores = 1L` for projection.
Checkpoint signatures include the backend and source identity. Completed
layouts can be reopened with `massive_open_projection()`. A file-backed
input is read in chunks, but the selected landmark reference and its fit
must still fit the declared RAM budget. No Metal route silently runs CPU
KNN or CPU projection.

The fixed-width KNN output is `prefix.indices.u32` plus
`prefix.distances.f32`, row-major with exactly `k` non-self entries per row.
IDs are one-based unsigned 32-bit integers; distances are nonnegative
float32. An exact-neighbor audit compares sampled rows with a streamed exact
search. Record mean recall, worst sampled row, audit-row IDs, effective
parameters, build seconds, query seconds, and peak RSS. Neither a high mean
nor a passing sample proves every row of a billion-row graph is correct.

## 4. PCA, UMAP, and t-SNE

The following equations state the computational objective; backend kernels
may differ in precision, scheduling, and reduction order. With centered
input `X_c`, rank-`r` PCA approximates `X_c = U_r S_r V_r^T`; scores are
`U_r S_r` and loadings are `V_r`. Randomized SVD finds a low-dimensional
range before this small factorization. The streamed covariance route forms
`X_c^T X_c` in bounded row blocks, then projects the scores in a separate
pass. This route is most attractive when the number of columns is modest.

### PCA

Ordinary CPU PCA uses blocked randomized SVD with BLAS-backed products;
Metal uses MPS block-subspace products; CUDA uses native randomized SVD or an
explicitly selected RAFT TSVD route where built. The result records which
method actually ran. A GPU request is not relabeled after a CPU fallback.

File-backed PCA makes bounded passes for means/scales and either accumulates
a covariance matrix for suitable widths or forms a bounded wide sketch. It
then projects score rows into a new float32 file. This makes the input
matrix nonresident, but the covariance/sketch and projection workspaces
still consume RAM or VRAM. When multiple CUDA devices are requested,
file-backed PCA partitions covariance or wide-sketch passes by input rows,
combines their statistics or sketch on the host, and distributes score-row
projection. The small decomposition remains on the host; this is not a
distributed eigensolver. The fit reports `fit_statistics_backend` or
`fit_sketch_backend` for the distributed passes and
`decomposition_backend` for the host eigendecomposition. The wide route
also reports CPU moments. A resumed multi-GPU fit verifies saved
per-device row intervals, counts, and device order against the requested
split before
reusing its statistics. The written scores can be reopened with
`massive_open_pca()`. A source-locked 10M x 64 covariance test on one,
two, and four A100 GPUs confirmed 5M fitting rows per device on two GPUs
and 2.5M per device on four, with sampled score differences below 2.1e-5.
PCA-call times were 5.03, 5.60, and 5.86 seconds respectively: fitting
was distributed, but this case did not gain PCA-call speed. Observed
process-tree RSS rose from 0.59 to 2.54 GB across those configurations.
The raw source identities and per-device memory traces are in
`benchmarks/linux/massive-data/evidence/hf-multigpu-core/README.md`.
Larger, beyond-host-RAM validation remains a separate release gate.
File-backed Metal PCA reads bounded row blocks, first computes column
means, then accumulates centered cross-products with the native Metal
matrix-multiply kernel, and writes projected score blocks to a float32 file.
Column sums, covariance
aggregation, and the small eigendecomposition remain on CPU. It supports
up to 1024 input columns and one CPU worker. A checkpoint preserves the
completed fit and projected score-row count; recovery does not resume a
partially completed covariance pass. Metal reports shared unified-memory
estimates, not a separate VRAM peak. Larger-data performance and memory
claims require dedicated Mac measurements.

The explicit API is `pca(x, ncomp = 2L, backend = "metal",
massive = "out_of_core", output = "scores.f32", chunk_rows = 10000L,
memory_limit = "512MB", n.cores = 1L)`, where `x` is a file-backed
`massive_matrix()` descriptor. The result records the Metal statistics
pass and CPU eigendecomposition separately; `massive_open_pca("scores.f32")`
reopens a completed fit. Wide and multi-device Metal PCA remain
unsupported and fail explicitly.

### UMAP

UMAP converts directed neighbor distances to locally scaled memberships,
combines opposite directions into a fuzzy union, and optimizes low-dimensional
coordinates with attraction and negative-sampling repulsion. The ordinary
route uses a compact in-memory graph and native CPU, Metal, or CUDA updates.
For a directed neighbor distance `d_ij`, local connectivity `rho_i`, and
bandwidth `sigma_i`, membership is one at `d_ij <= rho_i` and otherwise
`exp(-(d_ij - rho_i) / sigma_i)`. The fuzzy union of opposite directed
weights is `w_ij + w_ji - w_ij*w_ji`. The `"binary"` graph mode instead
uses unit weights on the symmetric neighbor union; it is a distinct
sensitivity analysis, not standard fuzzy UMAP.
The experimental full route stores symmetric fuzzy edges as CSR, streams
edge batches each epoch, and keeps coordinates in CPU RAM, explicit CPU
`mmap`, Metal shared memory, CUDA device memory, or explicit CUDA managed
memory. `mmap` limits
explicit application buffers, not OS page-cache usage; CUDA managed memory
may page through host RAM. The default CUDA full layout must fit available
VRAM. Multi-GPU CUDA synchronizes updates through NCCL, but currently
replicates the full layout on each GPU. It should not be described as a
memory-distributed layout or an automatic acceleration.
The coordinated optimizer accumulates quantized edge deltas before each
owner update. Fixed-point 100,000-row synthetic runs matched independent
repeats and checkpoint restarts on two and four GPUs; these do not replace
real-data quality tests. Result metadata separates blocking NCCL reduce/
gather time from full epoch-finalization time, which also includes owner
updates. The former includes host dispatch and device barriers, not only
wire-transfer time.
The Metal full-graph route accepts a prepared symmetric fuzzy CSR graph and
file-backed 2D initialization. Its CPU feeder reads bounded graph rows,
applies the same edge-sampling schedule as the CPU route, and sends eligible
edges to a native Metal kernel. The kernel accumulates attraction and sampled
repulsion with fixed-point atomic coordinate updates. The entire coordinate
layout, but not the full input matrix or graph, must fit Metal shared memory.
With `layout_storage = "memory"`, host initialization is resident. With
`layout_storage = "mmap"`, host initialization and output use a writable
`.f32.part` mapping; the native Metal layout remains resident in unified
memory. The mapped option avoids a second resident host layout, not the
Metal working set. On success the mapped file is synchronized and renamed
to `.f32`; an interrupted run retains `.part` for checkpoint resume.
`layout_mmap_bytes` is the mapped file size, while
`metal_buffer_bytes_estimate` describes shared buffers; neither is measured
peak RSS. OS page-cache use is outside `memory_limit`. A separate Metal
working-set preflight rejects an oversized layout. This is not a disk-paged
Metal layout, a multi-Metal route, or an exact numerical replica of the CPU
update order. The route records `optimizer = "streamed_metal_atomic"` and
supports completed-epoch checkpoint/restart. Dedicated GPU VRAM is reported
as unavailable because Apple silicon uses unified memory.

Use `massive_umap_optimize(fuzzy, init, "umap.f32", backend = "metal",
layout_storage = "mmap", memory_limit = "2GB", checkpoint = TRUE)`.
The equivalent high-level `umap()` call accepts a prepared fuzzy graph,
file-backed initialization, `massive = "out_of_core_graph"`, and the same
Metal storage controls. Graph weighting and fuzzy symmetrization are CPU
preprocessing stages; the optimizer itself runs on Metal. A 3D or `devices`
request fails explicitly.
For file-backed **landmark** UMAP on Metal, a bounded reference is fitted
with the ordinary Metal route. Exact Metal query-to-landmark search writes
neighbor IDs and distances to disk, and Metal KNN interpolation projects
query batches into a row-major float32 layout. The reference stays resident
and UMAP refinement must be set to zero epochs; this is not full-graph UMAP.

### t-SNE

The package builds sparse conditional probabilities from KNN distances,
symmetrizes and normalizes them, then alternates attractive sparse-edge
updates with FFT-grid approximated repulsion. The production compact-support
policy uses approximately `k = perplexity`; with exactly `k = P`, the
conditional probabilities can approach uniformity. This is a methodological
choice, not a drop-in equivalent to wider-support comparators. Perplexity,
support width, KL, trustworthiness, and neighborhood preservation should be
compared in the publication experiments.

For each row, binary search selects a Gaussian bandwidth whose conditional
neighbor probabilities have target entropy `log(P)`. Symmetrization gives
`p_ij = (p_{j|i} + p_{i|j}) / (2n)` on the retained sparse support. The
low-dimensional Student-kernel probabilities `q_ij` are optimized against
`KL(P || Q) = sum_ij p_ij log(p_ij/q_ij)`. FFT interpolation approximates
the global repulsive sum; sparse edges supply attraction. Early
exaggeration, adaptive gains, momentum, and recentering alter the trajectory,
so iteration counts and initialization are part of the result identity.

Ordinary 2D and 3D fits use native CPU, Metal, or CUDA FFT implementations.
The experimental full route reads a normalized CSR affinity graph each
iteration and keeps coordinate, update, and gain state resident on CPU or
CUDA. It uses fixed early and normal iteration counts, not automatic KL
stopping. A two-to-four-GPU CUDA fit coordinates attraction and state
updates via NCCL, while global FFT repulsion remains on one GPU. Running
independent per-GPU embeddings would not produce a valid full-data t-SNE.
Full-graph CUDA t-SNE resolves the FFT grid at planning time, records that
grid in the checkpoint identity, forces the same value during the native
call, and rejects a reported grid mismatch. A resumed fit therefore cannot
quietly switch grids through `FASTEMBEDR_TSNE_FFT_GRID`. This has local
contract and checkpoint tests; a fresh two-GPU runtime rerun is still due.
For file-backed **landmark** t-SNE on Metal, the ordinary Metal fit embeds
the bounded reference. Exact Metal landmark neighbors are saved on disk,
then the native Metal fixed-reference transform writes 2D query batches.
It does not coordinate a full-data attraction/FFT optimization. Metal
file-backed full-graph t-SNE remains unsupported.
Making it a genuine full-graph Metal route requires a bounded affinity-edge
feeder, Metal attraction updates on one global layout, one global FFT
repulsion calculation per iteration, and checkpointed optimizer state.
Loading the entire affinity CSR into the ordinary Metal fit would not meet
the file-backed memory claim.

## 5. Clustering and landmarking

`knn_graph()` constructs an undirected graph from neighbor IDs, optionally
using shared-nearest-neighbor weights. `graph_cluster()` runs native Louvain
or Leiden on CPU, Metal, or CUDA, and Walktrap on CPU only. Louvain performs
local community moves and graph coarsening; Leiden adds refinement before
aggregation. Walktrap uses random-walk-based agglomeration. The file-backed
Louvain and Leiden implementations stream a full graph on CPU and save
assignment/level state. File-backed Walktrap is **partitioned approximate**;
partition boundaries and vertex order can affect it, so it must not be
represented as exact global Walktrap. Full-graph CUDA Leiden/Louvain have
an optional cuGraph-Dask bridge through `massive_cluster()`. A small
two-GPU modularity audit passed, but four-GPU, large-graph, and
beyond-VRAM validation remain open.

File-backed Metal landmark Leiden/Louvain selects a bounded reference,
constructs its KNN graph with native Metal search, and runs native Metal
community optimization on that resident reference graph. Exact Metal
query-to-landmark search writes neighbor rows to disk; CPU weighted voting
streams those rows to produce one label and confidence per source row. The
result reports `backend = "metal"`, `graph_backend = "metal"`, and
`assignment_backend = "cpu"`. Apple shared memory has no independent VRAM
peak here: `peak_vram_bytes` is unavailable, while
`metal_buffer_bytes_estimate` estimates graph-buffer requirements. This is a
landmark approximation, not a full-graph Metal fit. Walktrap and full-graph
Metal clustering reject Metal requests explicitly.
Full-graph Metal Leiden/Louvain would require bounded CSR edge staging with
globally synchronized labels and community volumes, followed by graph
contraction and Leiden refinement without loading the full CSR into RAM.
The current native Metal kernels accept a resident CSR, so they cannot be
used unchanged for that claim. Walktrap remains CPU-only by design.

For a file-backed `x <- massive_matrix("data.f32", nrow, ncol)`, a
landmark community fit is:

```r
communities <- massive_cluster(
    x, method = "leiden", massive = "landmark", landmarks = 10000L,
    k = 30L, output = "communities", backend = "metal",
    knn_method = "exact", n.cores = 1L, memory_limit = "8GB"
)
```

Choose `landmarks` and `memory_limit` to fit the resident reference graph;
the `communities.clusters.u32` and `communities.confidence.f32` outputs
contain all source rows.

The ordinary graph builder collapses reciprocal directed KNN edges into a
compact undirected representation. Its weight choices are Jaccard
shared-neighbor similarity, inverse distance, and binary adjacency; optional
mutual-edge and weight filters change the graph before clustering. Ordinary
CPU community optimization uses native C++ and double-precision graph
weights. CUDA and Metal run local moves/refinement on float32 CSR using
device kernels; package-owned C++ performs coarse-graph assembly between
levels. GPU community assignments need not be bitwise identical to CPU
assignments because floating-point atomics and scheduling differ.

Landmark mode selects a manageable reference subset, fits that subset, and
projects all other rows against fixed reference coordinates. It is an
approximation to a full fit, even when every input row receives output
coordinates. Multi-GPU landmark projection distributes independent query
rows; this does not make the reference fit multi-GPU. Full-versus-landmark
time, peak memory, neighborhood scores, and label structure should be
reported on identical source rows before using landmark results to support
a full-data claim.

## 6. Storage, recovery, and resource accounting

Raw `.f32` input is little-endian row-major float32 and requires explicit
dimensions. `.fbin` prepends two little-endian unsigned 32-bit dimensions.
Descriptors record size and modification time; changed sources fail
validation. Graph CSR uses `.offsets.u64`, `.indices.u32`, and
`.weights.f32`. CSR offsets are zero-based byte-independent edge counts;
vertex IDs in public KNN files are one-based. A completed graph's manifest
and validation scan are part of its contract, not optional decorations.
For `n` rows, width `p`, and `k` neighbors, the input takes about `4np`
bytes, the fixed-width KNN pair takes `8nk` bytes, and a CSR graph with
`E` directed edges takes `8(n+1) + 8E` bytes before metadata, temporary
sorting runs, checkpoints, and layout files. These formulas are lower bounds
for disk planning, not peak-disk estimates.

For Deep1B at one billion rows, 96 float32 columns, and `k = 30`, the
source `.fbin` is about 384 GB and one fixed-width KNN graph is about
240 GB. A symmetric CSR graph can approach 480 GB if each directed KNN
edge survives symmetrization in both directions. These are decimal GB
and do not include another method's graph. Let `D = n*k` be directed
input edges and `U` the exact number of positive undirected pairs.
The external sort first reserves `19D + 8(n+1)` bytes for pair runs and
their bounded merges. After sorting the 12-byte directed-pair records,
it scans them to count `U` and checks the remaining phases against
`max(19D, 12D+24U, 40U) + 8(n+1)` bytes. The bound covers pair
and row-run overlap, row-run merging, and final CSR output. At most 32
of 63 runs are merged at once, and the smallest group occupies at most
`32/63` of its phase's run bytes. Pair merging therefore stays below
`19D`; row merging and final CSR output stay below `40U`. Orientation
uses the sign bit of a nonnegative float32 weight, including signed
zero; graph values are unchanged. The sorter merges the smallest
bounded groups of runs and checkpoints each replacement before deleting
its source files. Reciprocal-pair, row-generation, and row-merge resume
states retain t-SNE's original normalization mass. A checkpoint made by
the older 16-byte sorter cannot resume under the compact-record build;
the source-identity check rejects it explicitly. For Deep1B at `k=30`,
the initial check is about 578 GB. If half of directed edges form
reciprocal pairs, the second bound is also about 728 GB; with no
reciprocity, it rises to about 1.21 TB and the job can stop before row
generation. These are conditional bounds, not measured Deep1B results.
The tighter admission bound does not shrink the input, KNN, or final CSR
files; it removes reservation for overlap the bounded merge cannot create.
They exclude the 384 GB input and 240 GB KNN graph already on disk.
A 2 TB total quota can still reject the job.
Completed UMAP and t-SNE CSR graph descriptors and manifests now report
`sort_resources$peak_payload_bytes`: the measured high-water mark of the
sorter's generated run and output payload files, including files while
they are being written. It excludes existing
input/KNN files and small sidecars; it is not a whole-filesystem peak.
`sort_resources$budget_bytes` is the second-stage bound based on the
observed pair count; the initial preflight uses only `D` and `n`.

The reproducible storage smoke test is
`benchmarks/linux/massive-data/benchmark_graph_sort_storage.R` in
`fastEmbedR-extra`. With 135,000 rows and `k=16`, the forward-only
ring produced 4,320,000 CSR edges and peaked at 87,480,008 sorter
bytes; its final bound was 87,480,008 bytes, down from 104,760,008.
The
reciprocal ring produced 2,160,000 CSR edges, peaked at 51,840,000
bytes, and needed a 52,920,008-byte bound. Initial admission for both
rings dropped from 52,920,008 to 42,120,008 bytes. Checkpointed and
uninterrupted files
matched byte-for-byte in both cases. The exact-count pass adds one
sequential read of the sorted pair runs. In these local runs, checked
and plain graph builds took 4.87 and 3.87 seconds (forward), and 3.00
and 2.57 seconds (reciprocal). These timings are not a controlled speed
comparison with the old build. These are
deterministic fixtures, not evidence that Deep1B fits the HPC quota.

The optional `sort_method = "bucketed"` UMAP and t-SNE builders read KNN
distances directly. They route unordered pairs by their lower vertex ID,
combine reciprocal weights within each bucket, and write completed CSR
rows immediately. Only reverse edges for later row buckets are staged;
consumed pair and row buckets are removed. t-SNE performs a bounded
in-place normalization pass over its completed weight file after the
global affinity mass is known. The global sorter remains available for
checkpointed construction; bucketed sorting rejects checkpoint/resume.
Tests compare complete CSR files byte-for-byte with the global path.
With 32-bit IDs and float32 weights, the pair buckets use `12nk` bytes,
while the reverse-row staging avoids a second full directed-edge copy.
The initial admission is now `12nk + 8(n + 1)` bytes: one copy of the
directed pair buckets and the CSR offsets. After writing them, the
builder measures the largest pair bucket and bounds the largest
reverse-row bucket. Before sorting, it checks the smaller of the old
`36nk` ceiling and `20nk + 6(B_pair + B_reverse)`, plus offsets.
`B_pair` and `B_reverse` are bucket sizes in bytes. The measured peak
must stay below this second budget. Weights remain exact float32 and
the kNN method is unchanged. Admission does not guarantee a skewed
dataset will finish under a particular quota; the builder can stop
before sorting if its observed buckets do not fit.
On a synthetic 100,000-row, 30-neighbor CPU fixture, final UMAP and
t-SNE CSR files were byte-identical to their global-sort counterparts.
The graph-build payload peaks were 72,757,824 versus 120,800,008 bytes
for UMAP and 72,755,856 versus 120,790,088 bytes for t-SNE, about 40%
lower. These figures exclude the input and KNN files and do not
establish a Deep1B-scale peak.
On the same synthetic construction at one million rows and `k=30`,
the final CSR files again matched byte-for-byte. The global/bucketed
sorter peaks were 1,207,999,048/520,701,456 bytes for UMAP and
1,207,908,448/520,568,296 bytes for t-SNE, about 57% lower. The
reproducible script is
`benchmarks/linux/massive-data/benchmark_bucketed_graph_space.R` in
`fastEmbedR-extra`; run it with `Rscript` and arguments `1000000 30`.
These are generated-payload peaks, not total SSD use or Deep1B results.
The same benchmark now reports stage payloads including the fixed KNN
files and, for the global UMAP route, its directed-membership file.
On that one-million-row fixture, these logical stage peaks were
1,447,908,448 versus 760,568,296 bytes for t-SNE and 1,567,999,048
versus 760,701,456 bytes for UMAP (global versus bucketed). These
figures exclude the original input, other retained method outputs,
filesystem allocation overhead, and concurrent jobs. They must not be
presented as a measured whole-run or billion-row SSD peak.
The script also accepts `scattered` as a third argument. This
deterministic fixture spreads neighbor IDs across row buckets while
keeping every neighbor distinct and non-self. At one million rows and
`k=30`, global versus bucketed sorter peaks were 1,207,889,968 versus
557,817,952 bytes for t-SNE and 1,207,980,568 versus 557,820,100
bytes for UMAP. Complete CSR files were byte-identical. Including the
fixed KNN pair and the global UMAP membership file, corresponding
logical stage peaks were 1,447,889,968 versus 797,817,952 bytes for
t-SNE and 1,567,980,568 versus 797,820,100 bytes for UMAP. These are
not filesystem or quota peaks. A four-pass sorter was also tested but
removed: on this fixture it saved under 0.3% beyond bucketed sorting
while roughly doubling runtime. The symmetric CSR itself dominated the
remaining peak. Further large exact-storage savings require a different
graph representation and matching optimizer readers, not more passes
over the same file format.
With the new admission check, a 1.2-million-row, `k=30` ring again
produced byte-identical CSR files. The bucketed t-SNE and UMAP sort
peaks were 618,724,752 and 618,726,624 bytes, versus 1,449,499,168
and 1,449,600,008 bytes for the global sort. Both bucketed runs
passed an 829,393,088-byte observed-bucket budget. This synthetic
case exercises the reduced second-stage budget; it is not a Deep1B
disk-peak measurement.
Reducing `k`, dropping edges, or quantizing weights would change the
scientific method and requires a separately named and quality-tested
route; it is not an implicit storage optimization.

The Deep1B benchmark reclaims t-SNE affinities after the t-SNE fit.
After full UMAP and, on CPU, Leiden complete, it also reclaims the
fuzzy CSR files and their manifest. The released payload is measured in
`reclaimed_payloads.csv`; its format occupies `8(n + 1) + 8m` bytes
for `n` rows and `m` symmetric edges. With `n = 1` billion and
`k = 30`, `m <= 2nk`, so the upper bound is about 488 GB. This reduces
space held during downstream scoring and concurrent campaigns, not the
graph-construction high-water mark. Retrying a graph consumer after
this point requires rebuilding the graph. PCA scores, final layouts,
labels, and the original input are not reclaimed by this stage.
The CPU Leiden run likewise retires completed contracted level files
after its final membership and modularity have been recorded; the
membership file remains for label scoring. Both reclaim steps reject
missing or unrecognized files instead of deleting arbitrary work files.
Its bucketed graph construction explicitly uses `consume_knn = TRUE`
at the last builder that needs the package-generated KNN pair: UMAP
in a combined run, or t-SNE in a t-SNE-only run. After all pair buckets
are flushed, the native builder closes and removes the KNN files before
sorting. It now stages rows from the end of the KNN pair and truncates
each consumed suffix, so allocated KNN bytes fall while pair-run bytes
grow. This leaves the graph weights and the final CSR unchanged. At
`k = 30`, the pair can occupy up to 240 GB at one billion rows, but it
no longer overlaps the complete 360 GB pair-run staging payload. The
original vector input is never removed. Graph manifests
and `reclaimed_payloads.csv` record the released bytes. The package API's
`consume_knn` option is off by default, rejects externally imported KNN,
and cannot be combined with graph-sort checkpointing. If construction
fails after release,
KNN must be rebuilt; do not use it when the pair is needed again.
No separate directed UMAP membership file is written. For `k = 30`,
the sequential full t-SNE/UMAP generated-data initial admission with
KNN rebuilding is now `12nk + 32n + 8` plus one bounded input block
(about 392 GB at one billion rows). A t-SNE-only or UMAP-only run uses
`12nk + 24n + 8` plus that block (about 384 GB). These bounds include
the overlap of shrinking KNN files with growing pair runs and the
conservative CSR offset allowance. Without KNN rebuilding, the
combined t-SNE/UMAP run retains its first KNN pair and still needs
`20nk + 32n + 8` (632 GB) at initial admission. For a single-method
run the planner
reports `36nk + 24n + 8` as the conservative post-staging ceiling,
down from `44nk + 24n + 8` (1.104 versus 1.344 TB at one billion
rows). A combined shared-KNN t-SNE/UMAP run reports `44nk + 32n + 8`
(1.352 TB): the earlier t-SNE affinity build must retain KNN for UMAP,
so the combined-run worst-case peak is not reduced by this option.
The Deep1B combined full-graph benchmark defaults to
`DEEP1B_REBUILD_KNN_FOR_UMAP=1` at 100 million rows or more; smaller
runs retain one KNN build unless this option is set explicitly. With
rebuilding enabled, t-SNE consumes KNN during its bucketed
affinity build, and the runner repeats the same KNN route and sampled
recall audit before UMAP. Set the variable to `0` to reuse one KNN build
when runtime matters more than disk space. The conservative combined-run
graph-stage estimate is then `36nk + 32n + 8` (1.112 TB at one billion
rows and
`k=30`). Both KNN builds and effective settings are recorded separately.
This trades substantial extra compute for an estimated 240 GB reduction
in the graph-stage overlap; it neither compresses the symmetric CSR nor
proves a measured billion-row SSD peak. Leiden work, concurrent jobs,
and unrelated files are not included. Because an approximate KNN
rebuild can yield different IDs, this is a repeated computation, not a
claim that the two methods consumed one identical KNN realization.
If the t-SNE affinity build or fit fails, the runner stops before the
second KNN build. A failure-injection test verifies this resource guard;
it does not change the peak of a successful run.
On an earlier local 2,000-row Deep1B-shaped smoke input, the rebuild
path completed PCA, full t-SNE, full UMAP, and Leiden. Both sampled kNN
recalls were 1.0, and the reported t-SNE graph-stage peak fell from
1,771,936 to 1,291,936 bytes. This is a logical generated-file
measurement on synthetic data; it is not an HPC quota or Deep1B peak.
Separate current-source 1,000-row runs did not yield byte-identical
t-SNE or UMAP coordinates; PCA and Leiden did match. Therefore the
rebuild option does not promise bitwise-identical layouts across runs.
On a controlled 300-row exact-KNN test, both final graphs and short
single-core t-SNE/UMAP optimizer outputs did match byte-for-byte. Its
reported t-SNE graph-stage peak fell from 72,288 to 48,288 bytes.
The 24,000-byte KNN pair was released while pair runs were staged;
the final graphs and short layouts remained byte-identical.
On a separate 6,000-row file-backed 32-feature HNSW test, the t-SNE CSR
files matched byte-for-byte. Its reported graph-stage peak was 5,839,452
bytes when retaining KNN versus 4,399,452 bytes after consumption,
exactly the 1,440,000-byte KNN pair. The sampled HNSW recall was 0.98125,
below the manuscript's 0.99 target; this is a storage/correctness test,
not an accepted neighbor-quality benchmark.
The native second-stage check uses the observed
bucket distribution. These estimates account for PCA scores and
layouts retained across stages.
Reverse-block KNN consumption is opt-in and only applies to package-built
KNN with bucketed sorting. An interrupted build cannot resume its partly
consumed pair; the pair must be rebuilt. The two KNN files are removed
if an error unwinds through R after truncation. An externally terminated
process may leave partial files that must not be reused. The reported
`peak_graph_stage_bytes` tracks the live KNN bytes and graph payload
through the build, but it is a logical file-size high-water mark, not
allocated blocks or a Deep1B measurement. The post-staging symmetric
CSR and clustering bounds do not shrink, so 1B admission still requires
the later observed-bucket check and sufficient quota.
`benchmark_streamed_knn_space.R` compares retained and consuming routes
on synthetic forward-ring KNN files. At 100,000 rows and `k=30`, both
UMAP and t-SNE CSR outputs matched byte-for-byte; their logical
graph-stage peaks fell from 96,757,824 to 72,757,824 bytes. At one
million rows, both matched and fell from 760,701,456 to 520,701,456
bytes, releasing the 240,000,000-byte KNN pair during staging. Local
construction times were 4.97/5.05 seconds (UMAP) and 4.60/4.79
seconds (t-SNE) at 100,000 rows, and 52.94/54.93 seconds (UMAP) and
50.34/51.64 seconds (t-SNE) at one million rows, retained/consuming.
These synthetic fixtures are not measured Deep1B filesystem peaks or
controlled throughput comparisons.
On a reproducible 5,000-row, `k=30` package-built exact KNN fixture,
`benchmark_consume_knn_space.R` measured a generated graph-stage peak
of 3,595,856 bytes with retained KNN versus 2,395,856 bytes with
consumption, for both UMAP and t-SNE. The 1,200,000-byte KNN pair was
released in each run; complete CSR files matched byte-for-byte. These
are logical generated-file peaks, not allocated SSD blocks or Deep1B
results. The persistent symmetric CSR format is unchanged.
The bucketed builder now writes sorted pair runs during its first pass,
without first writing and then recopying unsorted pair buckets. RAM for
the concurrent sort buffers remains bounded by the existing capacity.
The completed CSR still matches the global sorter byte for byte. On a
deterministic one-million-row ring fixture, the measured bucketed sorter
peaks remained 520,568,296 bytes for t-SNE and 520,701,456 bytes for
UMAP; the final symmetric CSR dominated both peaks. This removes a
temporary edge-file write/read cycle but does not establish a lower
whole-run SSD requirement or a measured Deep1B peak. A substantial
further reduction needs a different graph storage format and readers,
with separate correctness and performance validation.
The benchmark's screening estimate excludes the already downloaded input
and container and applies a 20% free-space margin. It is not a measured
peak or a guarantee for skewed buckets or concurrent independent jobs.
For several independent Deep1B full-graph fits, use
`deep1b/submit_storage_budgeted.py` to group jobs into waves bounded by
known graph-stage space plus any reserved CPU clustering space.
It uses the existing per-run post-staging graph bound, including the
KNN-rebuild option, and requires the sum of bounds in each wave to stay
below 80% of both reported free quota and physical free space. Later waves
depend on successful completion of every job in the preceding wave. With
one billion rows, `k=30`, KNN rebuilding, and 2 TB free, the graph-stage-only
preview places CPU, one-GPU, and two-GPU routes in three waves: at most
1.112 TB of estimated generated graph-stage files at once, versus 3.336 TB
if all three started together. A CPU Leiden reserve can change or block
that plan. This reduces simultaneous graph-stage demand, not the 1.112 TB
per-run bound or the size of the downloaded input. It is a planning bound,
not a measured Deep1B SSD peak; jobs outside this launcher can consume
the same quota, and a failed earlier wave deliberately prevents later
waves from starting. The existing runner removes completed payloads after
scoring and retains small metrics and figures. CPU submission requires
`--cpu-clustering-reserve-bytes`, because the graph-stage bound does not
include Leiden's contracted levels; no tested Deep1B value is available
for this reserve yet. GPU-only waves need no Leiden reserve. With less
free space, `--admission initial` uses about 392 GB for the initial
one-billion-row graph check when KNN is rebuilt and consumed, instead
of the 1.112 TB later bound. Without rebuilding in a combined run,
the initial check remains 632 GB. It needs
`--accept-late-space-failure` on submission: after staging the pair
buckets, the native builder measures their distribution and may still
stop for insufficient SSD before sorting. This is an admission policy,
not a reduction in actual peak space or a promise of completion.
The native second-stage check reads filesystem free space, which may
not expose a per-user HPC quota. Where quota is binding, reserve the
reported `worst_case_bytes` or monitor remaining quota independently;
an initial `READY` status alone is not a quota guarantee.
The local 2,000-row Deep smoke completed PCA, KNN, full t-SNE, full UMAP,
and Leiden after reclaiming 1,509,222 bytes of intermediates; all PCA,
t-SNE, and UMAP coordinate rows were present and finite. That smoke
validates stage dependencies, not a billion-row disk peak or a speedup.
An updated 2,000-row UMAP-only smoke completed PCA, KNN, bucketed fuzzy
graph, full-row UMAP, and Leiden, reclaiming the 480,000-byte KNN pair.

Checkpointed routes save progress at completed blocks, epochs, or
iterations. Resume validates source and parameter identity and partial-file
sizes. A successful checkpoint is not a substitute for checking final row
count, finite coordinates, input identity, and scientific quality. The
output prefix and sidecar files must remain together until completion.
Coordinated CUDA PCA, UMAP, t-SNE, kNN, and row-projection checkpoints also bind
the selected CUDA-visible IDs to physical GPU UUIDs. These routes require
`gpuinfo >= 0.2.0` and `jsonlite` to resolve the map; a changed map
rejects resume rather than silently continuing on another device.

Report storage and memory separately:

- **Input bytes:** on-disk matrix size, never included in process RSS.
- **Output/work bytes:** KNN, graph, layout, checkpoints, and temporary
  shard files; use peak occupied disk, not just final artifact size.
- **Peak host RSS:** observed maximum process resident set, including mapped
  pages actually resident; an algorithmic buffer estimate is not peak RSS.
- **Peak GPU memory:** observed process use for each device and the aggregate;
  an allocation request for two GPUs is not proof both performed work.
- **Time:** one matched end-to-end call boundary for primary comparisons;
  graph build, fit-only, scoring, and plotting times go in separate displays.

Quality uses fixed input row IDs and, when applicable, exact-neighbor
ground truth. `evaluate_embedding()` samples resident inputs for
trustworthiness, continuity, neighborhood preservation, pairwise structure,
and local-radius density diagnostics; it is not a complete billion-row
quality census. For unlabeled Deep/Turing vectors, use neutral coloring or
external ground-truth labels, never algorithm-derived cluster colors as if
they were source classes.

A [current-source labeled MNIST check](../benchmarks/linux/massive-data/evidence/hf-labeled-quality-current-20261014/README.md)
fitted 20,000 rows from one shared exact graph. Its coordinated two-GPU
UMAP layout was byte-identical to the one-GPU layout and took 2.740 versus
5.233 optimizer seconds. t-SNE's neighborhood and label scores remained
close, but its two-GPU optimizer took 3.065 versus 1.783 seconds. These
fit-only measurements establish neither a large-data break-even point nor
per-process GPU-memory reduction.

## 7. Reproduction and implementation references

The matrix/KNN/backend example prepared for release validation is
`inst/examples/jss_manuscript.R` in the package source. Source owners above
are the entry points for a code audit. Native implementation entry points
include `src/native_knn_bridge.cpp`, `src/native_knn_cuda_impl.cpp`,
`src/native_knn_metal_impl.mm`, `src/fast_knn_umap.cpp`,
`src/tsne_neighbors.cpp`, `src/massive_matrix.cpp`,
`src/graph_clustering.cpp`, and the CUDA/Metal clustering kernels.
Package build flags,
required GPU libraries, and native validation are described in the package
`docs/implementation.md` and `docs/backend-capabilities.md`.

The shortest reproducible CPU workflow is:

```r
library(fastEmbedR)
x <- scale(as.matrix(iris[, 1:4]))
nn <- precompute_knn(x, k = 15, backend = "cpu", n.cores = 1)
y_umap <- umap_knn(nn, graph_mode = "fuzzy", backend = "cpu", seed = 4)
y_tsne <- tsne_knn(nn, perplexity = 5, backend = "cpu", seed = 4)
pc <- pca(x, ncomp = 2, backend = "cpu", n.cores = 1, seed = 4)
stopifnot(nrow(y_umap) == nrow(x), nrow(y_tsne) == nrow(x))
```

The complete version, including an explicit backend check, is in
`inst/examples/jss_manuscript.R` and should be run against the source-locked
release. Do not interpret the elapsed
time of the two KNN-input fits as including `precompute_knn()`.

NVIDIA cuVS provides CUDA neighbor-search primitives, RAFT supplies an
optional truncated-SVD implementation, cuFFT supplies CUDA Fourier
transforms, and NCCL coordinates supported multi-GPU optimizers. Metal
Performance Shaders provides Apple GPU matrix operations. BLAS/OpenBLAS
accelerates supported CPU matrix products. New development runs are
configured to record a `gpuinfo` 0.2.0 hardware manifest before fitting;
archived runs without that file must not be described as having it. Its
`gpu_memory_sample()` and `gpu_memory_peak()` can attribute observed process
memory to visible GPU UUIDs; neither gives an allocation high-water mark.
In PID-isolated containers, NVIDIA may report host PIDs that are not visible
under the container's `/proc`. The locally tested gpuinfo correction marks
those samples unavailable rather than zero; it is not part of the archived
0.2.0 source used by the current Hugging Face jobs. Their whole-card peaks
remain diagnostic rather than process-attributed measurements.
`nccl_info()` establishes library visibility and version, not successful
communication between devices. fastEmbedR checks its own NCCL build and
must still validate a coordinated fit. `gpuinfo` does not implement the
optimizer communication. Dependency names identify roles, not a claim that
every backend uses every library.
NCCL exposes reduce-scatter and all-gather for an owner-sharded update,
but using those collectives alone would not remove the present replicated
coordinate layout or distribute t-SNE's global FFT. Neither memory-saving
route is implemented or claimed here.

For the t-SNE repulsion stage, single-process cuFFT Xt can distribute a
single 2D transform across several GPUs. cuFFTMp targets multi-process
distributed transforms and is not a drop-in for the current coordinator.
The present FFT grid is at most 1024 cells per side. The current source
records its lead-GPU execution with CUDA events as
`gpu_stage_seconds$repulsion`, separately from CPU enqueue, graph-visit,
and attraction wall times. These intervals may overlap and must not be
summed as an end-to-end duration. The timer needs a CUDA hardware run
before it is used as benchmark evidence. A library change should follow
a matched stage-time and per-device-memory study;
NVIDIA does not guarantee that multi-GPU cuFFT is faster for a given
transform. See the [cuFFT multi-GPU API](https://docs.nvidia.com/cuda/cufft/)
and [cuFFTMp process model](https://docs.nvidia.com/cuda/cufftmp/usage/differences.html).

cuML Dask also offers distributed nearest-neighbor fitting and queries,
but its documented input is a Dask-cuDF dataframe. It is a useful
comparator, not a drop-in replacement for the current file-backed
exact/IVF/HNSW shard interface. RAFT's documented communication model
is one process per GPU, whereas this package's optimizer coordinator
keeps multiple CUDA contexts in one process and uses NCCL directly.
Neither library removes the need to validate owner updates, global
t-SNE repulsion, and below-RAM input handling. See the
[cuML Dask NearestNeighbors API](https://docs.rapids.ai/api/cuml/stable/api/generated/cuml.dask.neighbors.nearestneighbors/),
[RAFT multi-GPU guide](https://docs.rapids.ai/api/raft/legacy/developer_guide/),
and [NCCL collective API](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/api/colls.html).

The newer [cuVS multi-GPU IVF-Flat API](https://docs.nvidia.com/cuvs/user-guide/api-guides/indexing-guide/multi-gpu)
can shard one index across GPUs or replicate it for query throughput.
Its documented build accepts a host matrix, and the guide does not
establish that an SSD-backed input larger than host RAM can be built
without full staging. It could replace duplicated per-GPU reference
indexes for inputs that fit its build contract, but is not currently
the package's beyond-RAM KNN route. Before adopting it, check the
installed cuVS headers and ABI, exact-ID recall on held-out queries,
peak host/each-GPU memory, restart behavior, and matched end-to-end
time against the existing cuVS IVF-Flat shards. The current route
remains explicit; no NN-descent or backend substitution is implied.

cuML's Dask UMAP wrapper distributes `transform()` of a model already fit
on one GPU; it does not implement a coordinated multi-GPU `fit()`. It
therefore cannot replace the full-graph UMAP optimizer described below.
The `device_ids` option in cuML's single-estimator UMAP is restricted to
partitioned NN-descent graph construction, not multi-GPU layout fitting.
That graph builder is also not fastEmbedR's selected exact/IVF KNN route.
cuML Dask PCA does fit across GPUs and is a useful matched comparator, but
its Dask-cuDF input contract alone does not prove that fastEmbedR's
file-backed, below-host-RAM boundary is met. See the
[cuML Dask UMAP API](https://docs.nvidia.com/cuml/26.10/api/generated/cuml.dask.manifold.UMAP/),
[cuML UMAP `device_ids` API](https://docs.nvidia.com/cuml/26.08/api/generated/cuml.manifold.UMAP/),
and [cuML Dask PCA API](https://docs.rapids.ai/api/cuml/legacy/api/generated/cuml.dask.decomposition.pca/).

The coordinated CUDA UMAP epoch uses NCCL reduce-scatter to deliver edge
updates to coordinate owners, then all-gather to refresh each device's
read-only coordinate view. The current implementation replicates that view
and its delta buffer on every GPU, so multiple devices distribute work but
do not pool VRAM for a layout larger than one GPU. The candidate deterministic
path stores each delta as a 64-bit fixed-point integer, doubling the delta
buffer relative to the 32-bit layout. Layout plus delta therefore requires
at least three layout-sized buffers per GPU, before graph and CUDA overhead.
NCCL's equal-size block collectives require padded owner ranges. RAFT Comms
could abstract this
communication for multi-process or multi-node deployment, but fastEmbedR's
current single-process coordinator does not use it and adding it would not
remove the replicated layout. See the
[NCCL collective API](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/api/colls.html)
and [RAFT Comms guide](https://docs.rapids.ai/api/raft/stable/using_raft_comms/).
The implicit one-GPU CUDA route applies in-place atomic updates. Passing
`devices = 0L` explicitly selects the synchronized owner-update route,
as does `devices = c(0L, 1L)`. A matched one-versus-two-GPU comparison
must use explicit devices on both sides; comparing the implicit route
against the coordinated route mixes two update rules. This distinction
is recorded in result optimizer metadata and checkpoint controls.
Coordinated UMAP and t-SNE results reject missing, negative, or nonfinite
stage timings, including synchronization, before reporting speed.
The owner-update route reads a frozen layout and reduces per-edge deltas
at each epoch. A 17-row, 2D/3D independent CPU check is
prepared in `hf-multigpu-core` for one positive-edge update and a separate
negative-sampling sequence. It has passed local reference tests but not
yet the two-GPU comparison in the earlier source. A source-locked two-A10G
run now passes all four 2D/3D attraction and signed-update references,
with maximum coordinate errors from 1.49e-8 to 1.92e-4 and exact restart
agreement. Eight-epoch ring quality nevertheless fell from 0.678 on one
GPU to 0.253 on two. This is an implementation check, not longer-run or
real-data quality validation. Raw evidence and the source hash are in
`benchmarks/linux/massive-data/evidence/hf-multigpu-core/README.md`.
At 100,000 synthetic ring rows and 300 epochs, the current-source
two-GPU route wrote every row and preserved about 5.4 of six immediate
ring neighbors among 30 embedding neighbors on sampled queries.
One versus two A100 GPUs took 3.840 versus 4.108 seconds for the UMAP
call; process-tree RSS was 443 versus 813 MB, with 1090 MiB sampled
process VRAM on each requested GPU. Global ring-distance rank
correlation remained near zero, and labeled real-data quality is still
untested. A restart after epoch four differed from an uninterrupted fit
by relative coordinate RMSE 0.3375. On two A10Gs, two independent
uninterrupted fits already differed by 0.3341, versus 0.3401 for a
resumed fit. Their local ring-neighbor scores and pairwise-distance
correlations were similar, but this does not prove deterministic restart
or convergence on real data. Floating-point atomic update ordering is a
plausible source of trajectory variation; the strict coordinate gate
still fails. That A10G repeat disabled only the unreliable
process-attributed VRAM sampler for diagnosis, not for release evidence.
In a newer source-locked explicit-device A10G check, 100,000 rows with
30 neighbors and 300 epochs took 19.893 seconds on one GPU and 10.109
seconds on two. The two-GPU fit split 1.56 billion edge visits evenly.
Nevertheless, independent uninterrupted and resumed fits differed from
the first by relative coordinate RMSE 0.252 and 0.245 respectively;
their synthetic local-neighbor scores were similar. This establishes a
speed benefit for this one fit, not deterministic restart or real-data
quality. The exact source and private job references are in the
`hf-multigpu-core` evidence README.
The current candidate replaces multi-GPU floating-point delta atomics
with signed fixed-point increments accumulated in 64-bit integer buffers.
An overflow bound based on graph edges, epochs, negative samples, and the
learning rate selects a power-of-two scale no greater than 2^24; the fit
fails explicitly if the safe scale would fall below 256. Integer addition
does not depend on edge scheduling order, and NCCL reduces the owner blocks
as unsigned 64-bit sums before decoding them back to floating-point layout
updates. The implicit single-GPU optimizer is unchanged; an explicit
one-GPU coordinated request uses the same fixed-point rule as multiple
GPUs. The chosen scale is returned in fit metadata, so quantization and
its additional VRAM cost are visible.
Compilation and a single-GPU repeat passed on Chiamaka. The first
source-locked two-A10G job completed its 100,000-row one-GPU fit but stopped
at a process-VRAM attribution gate: the container reported no process
samples even though whole-card GPU memory was sampled. A diagnostic rerun
preserved the missing-process flag and completed the numerical checks.
An isolated GPU probe confirmed the cause on Hugging Face: the fit sees
container PID 1 while `nvidia-smi` reports its host PID, which is not
resolvable from that PID namespace. The benchmark now marks such samples
`pid_unmatched` rather than silently relabeling card-wide use as process use.
In the 100,000-row synthetic-ring rerun, one/two-GPU coordinates were
byte-identical, as were an independent two-GPU repeat and a restart from
epoch four. Optimizer time was 20.390/10.129 seconds, with equal two-GPU
edge work. Exact local ring-neighbor preservation on 512 sampled rows was
1.000 in the new layout. The separate global ring-distance correlation of
0.00790 is a different metric, not evidence of a local-neighbor collapse.
This clears a synthetic reproducibility gate, but not real-data quality,
larger-scale speed, or a beyond-VRAM memory boundary. Whole-card memory
must not be reported as process-attributed VRAM.
The same source archive also passed a four-A10G 100,000-row, 300-epoch
run: all four GPUs processed 390 million edge visits, and one/four-GPU,
repeat, and restarted layouts were byte-identical. Optimizer time was
19.636 versus 7.074 seconds within that job. Peak process-tree RSS rose
from 619 MB to 1,447 MB; sampled whole-card peaks were 754 MiB on one
active GPU versus 422 MiB on each of four GPUs. Process attribution was
unavailable, so these figures do not establish a memory boundary.
The coordinator now rejects a completed multi-GPU UMAP fit if the returned
graph dimensions differ or the sum of per-device edge visits differs from
the reported current-call visits, including after checkpoint resume. This
is a completeness invariant, not a layout-quality measurement.
CPU-only checkpoint contract tests also verify that UMAP and t-SNE reject
resumption after a source-file change, a changed CUDA device order, or a
changed device UUID. They do not replace an interrupted GPU runtime test.

The t-SNE coordinator computes one global FFT repulsion on the first
requested CUDA device (coordinator rank zero),
then reduces attraction gradients by coordinate owner before synchronized
updates and recentering. The current candidate feeds each device's bounded
CSR row range from an independent host reader. This concurrent feeder has
compiled and completed a source-locked two-A10G test at 100,000 rows:
the one- and two-GPU coordinates agreed within 1.86e-9 maximum absolute
difference, but two GPUs were slower. This three-iteration probe does not
establish converged quality or a performance crossover. Each GPU retains
the full coordinate view; it does not pool layout VRAM. The reported
`attraction_sync` time may include a wait for queued FFT work, while UMAP's
`synchronization` time includes owner updates. Neither is a measurement of
NCCL communication alone.
The result records `resources$fft_owner_device` as the first requested CUDA
device. A two-GPU t-SNE run therefore does not imply two-GPU FFT work.
Both coordinated optimizers also report `resources$owner_wall_seconds`:
the elapsed wall time spent feeding and processing all owner ranks across
iterations. Per-rank graph-read and device-step maxima overlap within that
interval and must not be summed as an end-to-end decomposition. The Deep1B
benchmark records this separately as `owner_wall` in its stage CSV.
NVIDIA's [multi-GPU cuFFT Xt API](https://docs.nvidia.com/cuda/cufft/index.html#multiple-gpu-cufft-transforms)
can distribute complex FFTs, but is not a drop-in replacement here: the
current 2D repulsion uses five forward and four inverse batched C2C
transforms plus owner-specific scatter/gather kernels. Xt would require a
new distributed FFT-buffer layout and measured transfer costs. Its
batched mode assigns separate transforms to GPUs; it would not by itself
partition each global density transform. The single-transform mode has
different output ordering and would need a separate integration. Its
documented inter-GPU bandwidth dependence and lack of guaranteed speedup
make a focused FFT-stage comparison a prerequisite to adopting it.
For a coordinated t-SNE fit, the returned device IDs and iteration range
must match the request, and summed per-device attraction visits must equal
the graph edge count times the iterations executed in this call. This
catches missing or duplicated graph work, not incorrect gradients or
embedding quality.

RAPIDS cuGraph exposes multi-GPU Louvain and Leiden through its Dask graph
API. fastEmbedR's optional bridge streams a symmetric fuzzy CSR graph into
canonical undirected edge partitions, constructs one distributed graph, then
writes one file-backed label per source row. Rows with zero CSR degree receive
distinct singleton communities after the distributed fit; a missing label
on any row with edges is an error. A graph with no edges is rejected.
Label export renumbers communities by scanning bounded row chunks and a
bit-packed presence table, rather than calling `np.unique()` on the entire
label file. This lowers worst-case exporter RAM pressure without changing
label order or modularity; low-community inputs may not save RAM, and
distributed graph construction can still need much more RAM
and VRAM. It is not evidence that billion-row clustering fits the current
GPU or host-memory budget.
The isolated-row export has a CPU-side contract test but still needs a
multi-GPU runtime rerun.
Requested CUDA-visible devices are mapped to UUIDs before launch; Python
checks full PCI domain/bus/device identity against `nvidia-smi`, normalizing
CUDA's four-digit and NVIDIA's eight-digit domain spelling, and uses the
matched physical indices for Dask workers and its
scheduler. The worker now requires the requested number of Dask workers and
`graph.is_multi_gpu()` after construction; the R caller verifies those
reported facts before accepting labels. Each Dask worker also reports its
PID and first visible GPU's PCI bus. The bridge maps those buses to the
requested UUIDs and rejects missing or duplicate GPU assignments. This
checks graph distribution and worker placement, not balanced work or speedup.
The worker records the requested method,
resolution, iteration limit, and seed; the R caller rejects metadata that
does not match the submitted controls. It independently recomputes
modularity on the source CSR and rejects incomplete labels or a nonfinite
score. Louvain rejects a
reported-score discrepancy above 0.005. Leiden retains the returned cuGraph
score as diagnostic metadata, warns on that discrepancy, and reports the
independently verified source-graph score as `modularity_final`. Leiden also
checks that each final community is connected on the source graph and fails
before finalizing labels if one is split. The independent `graph_audit` result
records the component count; its union-find scan reserves about eight RAM
bytes per vertex in addition to the modularity buffers and obeys the stated
RAM budget. The fit uses a GPU-resident distributed graph; it does not
support a graph larger than aggregate VRAM.
The caller rechecks the validated CSR identity before and after the
independent graph audit. A file changed during fitting is rejected even if
its size and modification time are restored; this check uses file status
change time and is not a full-content hash.
The caller also hashes the loaded fastEmbedR implementation and the Python
cuGraph worker before fitting, checks both again afterward, and stores
`implementation_identity` and `python_worker_md5` in the result. A stale
partial labels file is rejected before a new fit rather than overwritten.
It requires Python cuGraph/Dask-CUDA, `gpuinfo >= 0.2.0`, `jsonlite`, two to
four initial visible devices and explicit free-RAM/VRAM headroom. The
host-RAM admission estimate allows one bounded CSR conversion buffer per
concurrent worker. `ram_staging_estimate_bytes` records that bound; it is
not a measured host peak. A measured launcher-plus-worker RSS above
`memory_limit` rejects the fit before labels are finalized.
There is no silent CPU fallback, checkpoint, initial partition, or Walktrap
CUDA route. The `n_iterations` control caps cuGraph levels rather than CPU
local-move passes
per level. cuGraph Louvain does not accept a seed, so non-default seed
requests fail instead of being ignored. Dask-CUDA device spilling is
disabled for this route. Its result records sampled, whole-physical-GPU
peak VRAM by UUID and rejects missing samples; those card-wide figures
can include other processes and are not per-process allocations. The
current bridge samples the launcher and each Dask worker PID reported
by Dask, including workers reparented outside the launcher tree. Worker
PID, bus, and UUID assignments remain visible in the GPU memory metadata. It
deduplicates descendant PIDs, rejects workers that exit or change PID
identity, and reports `measured_ram_scope = "launcher_and_workers"`.
This is a sampled fit-process RSS sum, not a machine-wide or cgroup
peak. The new telemetry has local
contract tests but has not yet been rerun on the two-GPU runtime. SSD
peaks still require an external measurement before a memory-boundary
claim. The
development probe in
`benchmarks/linux/massive-data/evidence/hf-multigpu-clustering/` used
earlier source and is not publication evidence. Its 1M/5M single-GPU
modularity checks passed; a 10M single-GPU graph did not fit 16 GiB, and an
older 10M discrepancy remains unresolved. The bridge still needs real-data
correctness, a larger performance crossover, and checkpoint support. The
[two-A10G package-bridge test](https://huggingface.co/jobs/tkcaccia/6acf9130c662881452240ac5)
on 1,024 synthetic rows labeled every row and matched independently scored
Louvain/Leiden modularity within 1.2e-8; sampled whole-card memory showed
both GPUs active. Its roughly 10-second R calls were dominated by Dask
startup and cannot establish speedup. See
the [cuGraph community API](https://docs.rapids.ai/api/cugraph/stable/api_docs/cugraph/community/)
and [distributed graph input API](https://docs.rapids.ai/api/cugraph/stable/api_docs/api/cugraph/cugraph.graph.from_dask_cudf_edgelist/).

A [four-A100 package-bridge audit](https://huggingface.co/jobs/tkcaccia/6acf9860c662881452241998)
used 100,000 synthetic ring vertices and one source archive on two and four
GPUs. Louvain labeled every row, kept planted groups separate, and matched
source-graph modularity within 4e-7. Its 2/4-GPU source scores were
0.987910/0.987853; R-call times were 17.4/19.9 seconds. Leiden also
labeled every row with connected, group-pure communities, but the cuGraph
25.06-reported scores (0.994055/0.994395) exceeded source-graph scores
(0.987675/0.987730) by 0.00638/0.00667. A separate NumPy weighted-edge
scan of the reconstructed source graph confirmed the R score to displayed
precision. The tested archive rejected Leiden, so the combined job failed;
the subsequent reporting-policy change passed local tests and a replay
against the archived 100,000-row GPU labels, returning 0.987675 with an
explicit warning. A
[fresh current-source fit](https://huggingface.co/jobs/tkcaccia/6acfb4945ccb47ba0f79e631)
then passed separate two- and four-GPU Louvain and Leiden runs on the same
100,000-row graph. Independent rereading of its labels confirmed every
row, group-pure assignments, and connected induced communities. Its
two-/four-GPU R-call times were 17.212/18.784 seconds for Louvain and
15.654/17.645 seconds for Leiden. The Leiden source scores were
0.987719/0.987783, while cuGraph 25.06 reported 0.994701/0.994463;
the warning and independently computed source score were retained.
This is evidence of a persistent score-reporting discrepancy, not a
Leiden speedup or real-data clustering quality result. The compact
[current-source evidence](../benchmarks/linux/massive-data/evidence/hf-multigpu-clustering/current-fit-100k-20261014/)
is source-locked; raw artifacts are in the private bucket.

Algorithm attributions and third-party notices are maintained in the
package's `inst/ALGORITHMIC_REFERENCES.md`, `inst/NOTICE`, and
`inst/THIRD_PARTY_DEPENDENCIES.json`. The final archived manual must retain
the source lock and corresponding citations from the submitted manuscript.

## 8. Remaining engineering and release gates

These are open gates, not features implied by a successful smoke test.
The source-locked Hugging Face runs under
`benchmarks/linux/massive-data/evidence/` use several source hashes;
results from different archives must not be treated as one matched
campaign.

1. **Freeze and validate the candidate.** Record the package, faissR,
   gpuinfo, benchmark-suite, container, and input identities together. Run
   the package tests and rebuild the image from those sources before the
   final campaign. Repeating a result under different source states is not
   a single comparable benchmark.
2. **Finish coordinated optimizer tests.** The fixed-point UMAP candidate
   passed byte-identical one/four-GPU, repeat, and restart checks on a
   100,000-row synthetic ring and matched one/two-GPU labeled-MNIST quality
   at 20,000 rows. Repeat recovery and matched quality on larger labeled
   data. The current t-SNE feeder passed a two-GPU synthetic comparison;
   labeled-MNIST quality was similar, but its two-GPU optimizer was slower
   than one GPU. Establish a larger-data break-even point and repeat/restart
   and KL gates under the same frozen source. A true GPU-memory boundary
   beyond one device still requires removing full-layout replication or
   explicitly bounding the replicated state.
3. **Audit KNN and PCA at scale.** Validate exact KNN IDs on small graphs
   with duplicates and ties, then audit untouched Deep/Turing queries after
   tuning. Report effective per-shard settings, recall, build/query time,
   duplicated reference reads, and peak storage. Separately validate PCA
   distributed statistics/sketch, host decomposition, and score projection;
   a multi-GPU projection alone is not a distributed fit. The 10M x 64
   covariance test verified fitting on all four GPUs and host-side
   eigendecomposition, but not a speedup or a beyond-host-RAM boundary.
   The exact scorer rejects overlapping tune and holdout query rows.
4. **Validate the cuGraph clustering candidate.** The optional source route
   has CPU-side edge, row-coverage, dispatch, identity, and modularity gates.
   The current-source 100,000-row synthetic gate passed on two and four
   GPUs, but four GPUs were slower. Compare representative real graphs and
   CPU reference partitions, assess 10M graph construction, and investigate
   the persistent cuGraph Leiden score discrepancy. Measure process-only
   per-device VRAM as well as the sampled whole-card peaks. GPU
   checkpoint/restart and true beyond-aggregate-VRAM graphs remain absent.
   Keep Walktrap CPU-only.
5. **Close the measurement gap.** Collect observed process-tree RSS,
   per-device process VRAM by UUID, peak allocated SSD blocks, and matched
   end-to-end time for every fit. The development runner now maps CUDA
   ordinals to `nvidia-smi` physical indices by UUID and rejects a mismatch.
   Older peak files without that mapping remain diagnostic if visibility
   was filtered or reordered. The process-group monitor now includes
   reparented PSOCK workers; its strict process-VRAM gate passed at 10M
   rows on two and four GPUs. The older
   HPC two-GPU monitor now requires a `gpuinfo` UUID manifest; the current
   Chiamaka image has gpuinfo 0.1.0 and must be rebuilt with 0.2.0 before
   that monitor can pass. Its GPU peak is device-wide and sampled, so
   concurrent processes can contribute to it. Estimated
   package buffers must not be reported as observed peaks.
6. **Establish publication-scale value.** Use identical rows and parameters
   for classic, file-backed full, and landmark routes. Include labeled real
   data for trustworthiness, neighborhood preservation, t-SNE KL, and label
   structure; use Deep1B windows of 1M, 10M, 50M, and 100M rows for
   scaling and memory. Run matched 4/8/16-CPU and 1/2/4-GPU cases, quantify
   the crossover, and keep failed or quality-regressed cases visible. Re-run
   the JSS comparators only after the implementation and timing boundaries
   are frozen.

## 9. Unified benchmark interpretation

The JSS manuscript, supplement, and
`benchmarks/linux/jss-review-validation/common/` manifests define the
canonical comparator and dataset list. A source-locked JSS campaign and the
Deep1B hardware matrix are independent submissions; CPU jobs must not wait
for L40S availability. The Deep1B matrix includes ordinary 1M-row CPU/CUDA
fits and file-backed 1M, 10M, 50M, and 100M fits. Each file-backed case
requests PCA, full-row KNN, t-SNE, UMAP, Leiden, and Louvain where the
selected backend implements that method. CPU uses 4, 8, or 16 workers;
CUDA requests one, two, or four GPUs on one node. Larger same-lane cases
may wait for smaller same-lane work to release scratch space; that is a
storage dependency, not a computational dependency. The `--plan` output
and submitted-job ledger disclose each dependency.

The current full-graph CUDA clustering bridge requires two to four GPUs
and a distributed graph that fits their combined free VRAM. Single-GPU
full-graph Leiden/Louvain are recorded as unsupported rather than silently
replaced by CPU fits. A 50M or 100M multi-GPU clustering memory rejection
is likewise a failed feasibility result, not evidence that the requested
fit completed. The PCA, KNN, t-SNE, and UMAP outputs from that campaign
remain individually inspectable; a failed all-method audit is never
reported as an all-method pass. NOMAD has a distinct contrastive objective
and is compared only in supported CUDA JSS runs, not relabeled as a UMAP
or t-SNE implementation or an out-of-core Deep1B route.

The Deep1B source supplies vectors but no class labels. Its full-row PNGs
count every finite coordinate in density bins and use an unlabelled color
scale; they do not color communities as if they were source truth. Label
structure belongs in the matched labeled JSS datasets. Time is reported
by stage and end-to-end; RSS is the observed process peak; GPU memory is
sampled by UUID and its scope is recorded. The Deep1B job monitor measures
process-attributed CUDA memory, whereas cuGraph's internal telemetry also
reports whole-physical-device peaks that may include other processes.
These quantities are not interchangeable. SSD peak means allocated blocks
under generated `work/` and `results/`; it excludes the already downloaded
input file, the container image, and concurrent campaigns. Estimates,
sampled peaks, and quota reservations must have separate column labels.

A result is manuscript-eligible only when its source/image/input identities,
method metadata, complete row count, full-row output size, stage timing,
memory scope, and method-specific quality audit are present. An image or
allocation alone does not establish multi-GPU acceleration: PCA must report
per-device fitting rows, KNN must report per-device query rows and held-out
exact-neighbor recall, and the coordinated optimizers must report positive
work on every requested device. Failed and unsupported cases remain in the
campaign ledger and are not silently dropped from denominators.
