# fastEmbedR implementation gaps after 3 November device checks

## Remaining work by type, 4 November 2026

| Work | Code state | Completion gate |
| --- | --- | --- |
| Multi-CPU, file-backed full-graph Louvain/Leiden | Isolated CPU candidate accepts 2-32 workers for bounded row-candidate preparation with ordered commits. Its first local-move pass now uses one core because early proposals become stale; later passes use the requested workers. Mac tests show exact partitions, modularity and moves across 1/4 cores, including Leiden. | Two paired Mac repeats cut four-core Louvain time from 0.534-0.535 to 0.427-0.428 s on 100k x30 and from 1.053 to 0.773 s on 50k x200; Leiden fell from 0.958 to 0.845 s. One core still wins. Larger batches did not help. Redesign and qualify true scaling before a speedup claim. See `benchmarks/macos/multicpu-fullgraph-20261104` and `benchmarks/macos/multicpu-firstpass-20261105`. |
| Multi-GPU CUDA clustering beyond combined VRAM | An isolated `gpu_storage="stream"` candidate keeps CSR, labels, degrees, and volumes in host storage; two to four CUDA workers process bounded row and edge batches. Louvain and Leiden have CPU graph contraction; Leiden also has CPU file-backed refinement. Two-A10G small correctness and artificial 8 MiB per-GPU pool qualification passed. | The 26.4 MB graph exceeded the artificial combined pool, not the A10Gs' physical 46 GB combined VRAM. Test real-data quality, multi-pass convergence, host RAM, runtime, true beyond-physical-VRAM scale, and hybrid Leiden connectivity before a capability/performance claim. Never test SSD streaming on UCT HPC. |
| Metal full UMAP quality | The optimizer exists, but paired Fashion-MNIST quality is below the CPU acceptance gate; snapshot and parameter sweeps did not solve it. | Correct the algorithm or its KNN policy and pass paired quality while retaining the intended speed benefit. |
| CUDA resident multi-GPU landmark UMAP | Coordinated reference fitting and sharded fixed-reference projection are in the candidate and built with CUDA/NCCL. | Complete the queued L40S device pilot, then real-data 2D/3D quality, memory and work-per-GPU tests. |
| Other experimental 3D and SSD routes | Metal 3D t-SNE has a `graph_access = "stream"` bounded graph-chunk option; CUDA file-backed 3D t-SNE and Metal/CUDA file-backed clustering have candidate code. | Establish scale, peak memory, quality and restart behavior on permitted machines. The Mac 100M Deep1B stress test remains postponed. |

The candidate is on a separate GitHub branch. Integration into main and a
source-locked benchmark are later gates, not missing source implementations.
The older chronological notes below describe narrower intermediate
candidates and should not override this current inventory.

## Later 4 November update

The user's added US$3 Hugging Face allowance funded a bounded two-A10G
CUDA clustering qualification. The first job failed before calculation
because the image lacked `xz`; a corrected, separately versioned job
completed small partition checks and a 100,000-row artificial-pool test.
The source hash, logs and limits are under
`benchmarks/linux/hf-stream-qualification-20261104`.

The isolated package now also routes in-memory matrices, resident graphs,
file-backed matrices and certified file-backed full graphs through
`graph_cluster()`. A Mac R 4.6 package build and focused tests passed.
`massive_cluster()` remains exported for older callers and advanced
benchmarks, but the public guide and vignette now use the unified entry
point. Full export reduction and benchmark migration are still pending.
The package source-style check passed. No change was made to the existing
source-locked HPC image; its L40S pilot remained queued for priority.

## HPC source-lock and qualification update, 4 November 2026

The reviewed combined package candidate was pushed to the separate GitHub
branch `codex/implementation-qualification-20261104` at commit
`b8251168e3b77093452876c10e1a79861d9660e5`. This is not a release or a
merged main branch. The full CPU test suite passed using a temporary R 4.5.3
compatibility copy, with hardware-dependent tests skipped; package source
style and diff checks passed. The exact R 4.6 CUDA/NCCL source built into a
new immutable HPC Singularity image. Its SHA-256 is
`144b878f42b8c10f2dc9bc3ee422c51caf5a090049c0f89027fdc27ad1f34773`.
CPU image build job `1570377` and a real Slurm warning-route test `1570378`
completed successfully. See `singularity/candidate_b825116_20261104` for
the source identity, build recipe, resident-only pilot and lifecycle tests.

The first two-L40S resident UMAP submit was rejected before scheduling for
missing the required `l40sfree` account. A corrected, separately versioned
one-case pilot is job `1570379`. At 14:28 UTC it remained pending for
priority; Slurm's provisional start estimate was 6 November. There is no
device-quality or cleanup result yet. The pilot uses a 160-row synthetic
matrix in memory and no SSD-backed scientific route. No wider HPC campaign
is admitted until this pilot has a verified terminal result.

Static review of the paired Metal UMAP quality gap found that its clean
atomic optimizer samples graph edges using a 32-bit hash and each row's
local edge slot, whereas the CPU clean atomic comparator uses a 64-bit hash
and a cumulative edge ID. Both use the same mathematical attraction and
repulsion coefficients, and the Metal snapshot update mode performed worse
than the atomic mode on the fixed-graph Fashion diagnostic. The different
random streams and atomic update order are plausible contributors, not an
established cause. Earlier parity-RNG and snapshot trials did not close the
Fashion gate; preserve their failed evidence and do not change the default
without paired device tests. The Mac currently rejects key-only SSH from
this PC, so no new Metal run was launched during this review.

## Update, 4 November 2026

The corrected two-A10G candidate job completed resident 2D/3D t-SNE and
UMAP, PCA and landmark PCA, Louvain and Leiden, and file-backed 3D t-SNE
parity and checkpoint/resume checks. Its evidence is in
`benchmarks/linux/hf-multi3d-20261104/`. A second completed two-A10G job
used a fixed 300-row, ten-class MNIST sample. CPU, one-GPU and two-GPU
2D/3D t-SNE and UMAP passed exact-neighborhood quality checks. The largest
two-GPU trustworthiness decline from CPU was 0.00295; the Louvain and
Leiden paired ARI results are in
`benchmarks/linux/hf-mnist-quality-20261104/`. These are small development
checks, not publication-scale quality, speed, or memory results.

The user stopped the obsolete source-locked Mac panel-v6 on 4 November.
Its 51/84 FlowRepository partial results remain preserved in Stefano.
The current priority is to finish and qualify candidate implementations
before starting a new full Mac benchmark.
Silvano's Mac has one Apple GPU. Metal device development and benchmarks on
that machine cover single-GPU execution only; multi-GPU work belongs to
CUDA on Hugging Face and the UCT L40S nodes.
The remaining critical quality gap is Metal UMAP: the paired FashionMNIST
gate still fails in the isolated optimizer experiments. Larger CUDA
file-backed, landmark and clustering quality checks remain outstanding.
Metal resident landmark PCA projection passed an actual-device CPU formula
comparison (maximum difference 5.23e-7). The user and administrator lifted
the UCT GPU pause; source review, immutable image, and lifecycle gates remain
before any L40S pilot. The ban on HPC file-backed science remains in force.

Static API audit found another implementation gap: resident `tsne()` and
`umap()` rejected `devices` when `landmarks` was requested. The isolated
candidate now forwards `devices` to the coordinated full-data fit when all
rows are landmarks, and rejects a partial landmark selection before its
reference fit. Focused routing and rejection tests, plus the existing
landmark regression file, passed in an isolated R 4.6 Mac build under
Stefano on 4 November. Scalar partial landmark requests now fail before
preprocessing, avoiding an expensive unsupported GPU allocation; its
public-entry test passed on the Mac. Actual all-row device testing remains.
`cluster_landmarks()` and resident landmark `pca()` accept coordinated CUDA
devices, while experimental file-backed landmark projection has a separate
sharded multi-GPU route. The isolated candidate now has a resident multi-GPU
reference fit and sharded query projection for partial-landmark t-SNE. A
two-A10G small device check passed in 2D and 3D on 4 November; larger
real-data quality, memory, and parity tests remain. A partial-landmark UMAP
multi-GPU route is now staged with reference-only negative sampling; its
CPU-only build and focused routing tests passed, but actual CUDA execution
and quality remain unqualified. See
`benchmarks/linux/umap-multigpu-candidate-20261104/README.md`. Do not route
either resident test through SSD on the HPC.

Native route audit: fixed-reference t-SNE query updates read only the
reference layout, so query rows can be sharded after a resident query KNN
materialization. The current CUDA UMAP refinement samples negative rows from
the entire assembled layout, including other query rows. Independent UMAP
shards change that objective. The staged route uses reference-only negative
sampling and records this choice; actual device quality and parity still
need measurement. The objective distinction follows from the CUDA kernels,
not from a completed device comparison.

On 4 November, Chiamaka's RTX 5060 Ti passed the first actual-device
resident `cluster_landmarks()` CUDA Leiden check after 13 idle samples
confirmed Bora was absent. The 160-row synthetic fit kept the 80 reference
labels fixed and assigned all query rows; its graph assembly and vote
correctly remained labelled CPU stages. The exact runner, library hash,
input checksums, result, and clean-context evidence are in
`benchmarks/linux/chiamaka-cuda-cluster-landmark-20261104/`.
This is a device smoke test, not a real-dataset quality or multi-GPU result.

This ledger separates code absence from code that exists but is not yet
integrated or qualified. It uses the isolated
`in-progress/cuda-multigpu-3d-20261103` source as the current combined
development candidate. The stopped Mac panel's original source and evidence
are preserved; only separate candidate libraries under Stefano were installed
for tests.

| Route | Current state | Remaining work |
| --- | --- | --- |
| CUDA resident 3D landmark t-SNE | Implemented; Chiamaka RTX 5060 Ti fit and held-out model projection passed; single-A10G check also passed inside the two-GPU job. | Integrate into the main package and run larger quality/performance tests. |
| CUDA resident 3D landmark UMAP | Implemented; Chiamaka fuzzy and binary cases passed with exact fixed-landmark coordinates and held-out projection. | Integrate and run larger quality/performance tests. |
| CUDA file-backed full-graph 3D UMAP | Implemented; two-A10G, 1,024-row smoke passed. | Larger data and quality tests; this smoke does not establish speed. |
| Metal file-backed full-graph 3D UMAP | Implemented in the isolated candidate. A 32-row, 256-edge Mac device check passed 2D/3D `memory` and `mmap` layouts plus interrupted 3D checkpoint/resume from epoch 4. | Integrate and qualify larger-data quality, performance, and memory use; the fixed graph smoke does not establish these. |
| CUDA file-backed full-graph 3D t-SNE | The isolated candidate has dimension-aware streamed input and checkpoint state, 3D cuFFT repulsion, directed CSR attraction, 3D updates and centering. Coordinated two-to-four-GPU code now uses dimension-aware NCCL counts, owner offsets, reductions and checkpoint gathering; it has a focused two-device 3D parity/resume test. A checksum-verified CUDA/NCCL package candidate built on Chiamaka. The guarded device probe did not launch because Bora became active. | Run the single- and multi-GPU 3D device tests when a GPU is idle, inspect numerical parity and recovery, then qualify quality, memory and larger graphs. The build and test code alone do not establish device correctness. Chiamaka evidence: `benchmarks/linux/chiamaka-cuda-stream3d-20261103/README.md`. |
| CUDA file-backed optimizer GPU identity | Explicit one-GPU UMAP and t-SNE plans previously omitted the physical GPU UUID. The isolated candidate now records it in results and checkpoint parameters. A 31-assertion Mac regression and a 10,000-row one-/two-A10G qualification both passed, including UUID and per-device work checks. | Integrate the fix into the main package and keep physical-device binding in future checkpoint audits. |
| Metal file-backed full-graph 2D/3D t-SNE | Experimental 2D and 3D routes now offer complete read-only Metal graph mapping or bounded SSD graph chunks through `massive_tsne_optimize()`, with checkpoint/resume. The 2D route uses deterministic fixed-grid accumulation: mapped and streamed Fashion-MNIST 5,000-row outputs matched bitwise across three seeds and five repeats per seed. On a 70,000-row, 3.36-million-edge graph, mapped and streamed 2D outputs matched bitwise after 250 iterations. A separate USPS 11,000-row graph also gave identical mapped/streamed coordinates. Focused tests passed 31 assertions; resident regressions passed 45 assertions with five CUDA skips and 82 Metal-stage assertions. Layout and optimizer state remain resident. The prior 3D mapped/streamed and checkpoint checks also passed. | Qualify larger graphs and other datasets, isolated peak memory, numerical quality, streaming throughput and recovery after interruption. The current 3D grid and near-field algorithm need scaling work before Deep1B 100M. The 2D 70,000-row exploratory fit took 0.365 s mapped and 1.482 s streamed, excluding graph construction; these are not publication speedups. Evidence: `benchmarks/macos/metal-tsne-fixed2d-20261103/README.md`. |
| Metal 3D landmark UMAP | Native 3D affine projection and fixed-landmark refinement are implemented in isolated `in-progress/metal-landmark-3d-20261102`; Mac device fit and held-out projection passed. | Integrate and run larger quality/performance checks after the source-locked panel audit. |
| Metal 3D landmark t-SNE | Native 3D affine projection and fixed-reference transform are implemented; Mac device fit, held-out projection, and 2D regression passed. | Integrate and run larger quality/performance checks after the panel audit. |
| Standalone GPU 3D `umap_init()` | Metal native 3D spectral initialization compiles and passes fixed-graph repeatability, 3D optimizer reuse, and 2D regression on the Mac. CUDA standalone graph rows reserve capacity from fixed KNN degrees and are sorted before spectral diffusion; 48-row and 1,024-row Chiamaka 3D repeatability passed. Prepared CUDA 3D optimization now runs its snapshot delta kernel; fuzzy and binary 48-row reuse and a 2D regression passed on Chiamaka. | Integrate the qualified Metal and CUDA routes and benchmark larger resident inputs for quality and speed. The ordinary CUDA UMAP graph path still needs a separate reproducibility audit. |
| Metal UMAP scheduled epoch alignment and quality | An isolated candidate fixes an epoch-zero update that disagreed with CPU; focused Mac tests passed. The default clean optimizer is nondeterministic on a fixed graph and start. A separate internal snapshot sampler repeats exactly in 2D/3D, but FashionMNIST quality still misses the paired audit gate; the source-locked public default is unchanged. | Improve optimizer quality without losing the Metal speed advantage, qualify across all datasets, then rerun the source-locked panel. Address full-pipeline KNN recall separately. |
| Metal full-pipeline KNN recall | The isolated candidate now selects native exact KNN for bounded inputs up to 50,000 rows, 16,384 columns, and 125 billion estimated row-pair feature operations. On Macosko2015_retina, the one-call Metal UMAP route scored 1.0 mean and minimum sampled recall in 1.128 seconds; the source-locked IVF route had a 0.6667 worst row. On FashionMNIST5k, exact and IVF each took about 0.12 seconds, while IVF's worst-row recall was 0.2667; the installed API selected exact. | Qualify the new policy across datasets. MNIST70k and other large IVF routes can still fail the strict worst-row recall gate; an MNIST target of 0.995 passed recall but took 8.143 seconds for KNN alone. Preserve the full-pipeline speed requirement. |
| Metal graph-clustering options | Resident Louvain and Leiden plus consensus, projection weighting, and small-group options run in the isolated candidate. File-backed multilevel Louvain and Leiden now run native Metal local moves/refinement on streamed CSR chunks; CPU contraction and audits are labelled. Louvain's 100,000-row synthetic full fit took 0.373 s versus CPU 0.392 s. Metal Leiden passed package-context tests and a connected MNIST70k fit; across three seeds its median fit time was 1.119 s versus CPU 1.301 s, with slightly lower modularity. A completed-level Metal checkpoint resumed to the same 128 labels and modularity as a fresh fit. | Qualify both methods on all real datasets and larger memory budgets, measure memory peaks, and rerun the source-locked benchmark. The present device checks do not establish manuscript-wide performance. |
| CUDA graph-clustering options | Implemented in the candidate. The two-A10G job passed basic Louvain and Leiden on 1,024 rows. Combined consensus, projection weighting, and small-group handling passed on Chiamaka's RTX 5060 Ti for both native methods. | Integrate and qualify larger graphs and multi-GPU option behavior; the small combined check is not a performance result. |
| CPU parallel clustering restarts and file-backed PCA projection | Implemented in the candidate; small CPU checks and two-A10G landmark PCA projection checks passed. | Integrate and benchmark scaling, accuracy, and checkpoint/resume on the intended datasets. |

Two bounded Metal probes on 3 November established that the M3 Ultra GPU
can read a memory-mapped file through a no-copy Metal buffer and can compute
3D t-SNE attraction from memory-mapped CSR arrays with 64-bit logical
offsets above the signed 32-bit limit. The latter used four vertices and
eight physical edges with a simulated large edge base; it is not a large
graph test or a working file-backed t-SNE route. Scripts, logs, checksums,
and limits are in `benchmarks/macos/METAL_TSNE_MMAP_PROBES_20261103.md`.
The isolated package candidate migrated resident 2D/3D Metal t-SNE CSR row
offsets and kernels to 64-bit edge positions. The kernels accept
chunk-relative CSR offsets and a first global row; resident callers pass
zero. The new 3D file-backed optimizer maps full read-only CSR files into
Metal buffers and supports checkpoint/resume. A small package-context
restart test and resident 3D regressions passed. Five 70,000-row
250-iteration fits from one fixed graph and start had identical output
checksums after replacing order-dependent float grid and nearby-pair sums
with scaled integer accumulation. This route is not bounded-chunk
streaming, and the nonzero-base chunk kernel remains a hardware probe,
not a package-level full-graph test. See
`benchmarks/macos/METAL_TSNE_MMAP_PACKAGE_20261103.md`.

The paused-and-resumed Mac panel snapshot and candidate device evidence are
at `fastEmbedR-results/mac-panel-partial-20261103/` in the project root.
At 09:44 UTC on 3 November, the user authorized suspending the panel for
Metal work. The panel and follow-on waiters are now stopped; the verified
current partial result copy and new Metal KNN evidence are under
`fastEmbedR-results/mac-panel-partial-20261103/paused-0944/`. Do not resume
the source-locked panel without a new user instruction.
The native 3D Metal streaming and checkpoint smoke logs are in its
`metal-stream3d-evidence/` folder. The tested source archive SHA256 is
`82d353966c88311699a79d82b71a033c6a063d77d5caa8bdfbf375043d86fc47`;
installed library SHA256 is
`8bc51c15e6eaa80b9267250212442ff96a74bc5b37cb9a646e325ab2eb563611`.
File-backed Metal Louvain development evidence is under
`paused-0944/metal-stream-cluster-evidence/`. The current isolated package
source archive SHA256 is
`57d84d1e0cbc48400e0b55d786cca6a5c3944f0ad7a26e84ab27b3fa7e3b7ab2`.
The original Mac panel remained paused throughout. File-backed Metal Leiden
now has a native device route in the isolated candidate. CPU contraction and
final modularity/connectivity audits are labelled; unsupported backends still
fail explicitly.
The current source archive SHA256 is
`b9c005479b76aa732bba5b25448fe63e3ad674c156858858cc39a415d50b12a2`.
Its Mac build and package-context `massive-leiden`, `massive-louvain`, and
`graph-options` tests passed. The three-seed MNIST70k median fit was 1.119 s
Metal versus 1.301 s CPU, with zero disconnected communities; same-seed Metal
labels repeated exactly. Modularity was about 0.001 lower on Metal and label
agreement varied by seed. Detailed tables and logs are under
`paused-0944/metal-stream-cluster-evidence/leiden/` in the local snapshot.
The Mac trial discarded 514 generated intermediate level files after audit,
retaining its final labels, scripts, logs, and CSVs; its evidence folder fell
from 225 MB to 2.2 MB. The original Mac panel stayed paused.
The later 128-row Metal Leiden checkpoint test resumed from a completed
first level and matched a fresh fit exactly. Its added package-context
regression passed on the Mac; the script and logs are in the same Leiden
evidence folder. Mid-level interruption recovery is not implemented.
The single-GPU CUDA identity regression ran against an isolated Mac R 4.6.1
installation at `Stefano/single-gpu-identity-20261103`; the focused
`test-massive-cuda-device-identity.R` file passed 34 expectations, including
single-device UUID remapping changing the checkpoint signature and the
default CUDA t-SNE route retaining its optional-dependency behavior. The
installed library SHA256 is
`f1b9477c2deb02cb4e231dcf0a84f3072e65af4570d6ad22e893296e249a12c5`.
Generated compiler objects were removed after the test; the entire isolated
test folder is 12 MB. The original panel remains suspended.
The corrected Hugging Face two-A10G job
`tkcaccia/6ae9e8ebc78863f9c631cf40` completed and passed its seven
bounded cases on a synthetic 10,000-row, 30-neighbor graph. The complete
log and six checksum-verified CSV tables are under
`benchmarks/linux/hf-scale-10k-20261103/revision-uuid-fix/`.
Two GPUs split the work but were slower than one here: UMAP took 1.800
versus 1.597 seconds and t-SNE 1.737 versus 0.972 seconds. This validates
native execution and numerical agreement, not a multi-GPU speed benefit
or manuscript dataset performance.
A separate 45-fit FashionMNIST Metal snapshot UMAP grid tested five negative
sampling rates and three repulsion strengths at 400 epochs on three seeds.
None met the paired silhouette gate; the best worst-seed decline was
-0.02657 versus the allowed -0.01. The checked script, CSV, and log are in
`benchmarks/macos/metal-umap-quality-parameters-20261103/`. Parameter
changes in this bounded range do not justify a default change; the optimizer
update rule still needs work.
At 14:14 UTC, Chiamaka's RTX 5060 Ti still listed a 2,814 MiB compute
context for PID 3754978. That process was a zombie child of Bora PID
3754143, which was in uninterruptible `D` state. No further GPU test was
admitted there; the later optional-dependency source edit remains Mac
mock-tested but unqualified on CUDA hardware.
On the real 70,000-row MNIST CPU-neighbor graph, 8,192-row chunks made
Metal slower than CPU (1.077 versus 0.720 s) despite similar modularity
and ARI/NMI. With 65,536-row chunks and three paired seeds, median Metal
time was 0.714 s versus CPU 0.734 s, but one seed was slower on Metal.
The candidate now chooses 65,536-row Metal chunks by default and leaves
CPU at 8,192; this is preliminary and needs real-dataset qualification
before any broad speed claim. Logs and per-seed CSV are in the same
`metal-stream-cluster-evidence/multilevel/` folder.
The KNN candidate now reports minimum pilot identity recall and worst
kth-neighbor distance ratio alongside mean pilot recall. MNIST and
FashionMNIST each had three of 256 pilot rows below 0.9 at target 0.99;
their kth-neighbor distance ratios reached 1.0348 and 1.0116. At target
0.995, MNIST had no pilot row below 0.9, but FashionMNIST still had one.
The separate Mac build and device smoke passed. This is diagnostic
metadata, not an IVF quality fix. Evidence is under
`paused-0944/metal-knn-exact-evidence/`; source archive SHA256 is
`a851d452021379d977e5f2f4e3daceff7d01f1e19e289cb6b2b09f1ffa926d51`.
At target 0.997, FashionMNIST's saved 64-row exact audit reached mean and
minimum identity recall of 1.0, but KNN took 16.84 seconds. The original
CPU 20- and 28-core KNN rows took 3.50 and 3.61 seconds. This stricter
target is therefore not a qualified default for the requested GPU speed
advantage. The script and log are `metal_fashion_knn_target_20261103.R`
and `target_997.log` in the same evidence folder. An adaptive or more
efficient Metal search is still needed.
A separate expanded-shortlist trial raised the per-group capacity from
128 to 256. On FashionMNIST, target 0.993 used 1,024 candidates but its
worst 256-row pilot recall remained 0.7667; target 0.995 selected the
direct reranker and had the same pilot minimum. The capacity change was
not merged. Its source and logs are under `shortlist256/` in the same
evidence folder.
Metal Louvain/Leiden graph-options evidence is in
`metal-graph-options-evidence/`; its source archive SHA256 is
`11cf564c8932821eb38c3bbc973453c2d8c8bb3476a93b836f027cac3978102a`;
installed library SHA256 is
`b7856b2e5cf763464ca4e5c4a6aa2b973a024e03b3f095350099878511268de7`.
Metal 3D initialization evidence is in its `metal-init3d-evidence/` folder.
The fixed-graph optimizer investigation and retained negative results are
summarized in `METAL_UMAP_DIAGNOSIS.md` beside the panel snapshot. The final
cleaned Metal smoke archive SHA256 is
`5211acf7dd32911067131ea5ed6e2e822f6d2fd108e8b9eda082114140bc4c7c`;
its 3D initializer and 2D/3D snapshot repeatability checks passed on the Mac.
The original panel was paused at 08:15:07 UTC for this isolated build and
resumed at 08:15:50 UTC; worker PID 4342 returned to active CPU use. The
Mac candidate source archive SHA256 is
`5247d1a44db9783ee30a2382973cd0e02a9adcb5d1487bee063941bd9346200a`.
The original CUDA initializer and graph diagnostic logs are in the companion
`benchmarks/linux/chiamaka-cuda-tsne3d-20261102/evidence-20261103/cuda-init3d-diagnostic/`
folder. Its fixed 48-row KNN graph dumps differed even after sorting by
endpoints. The corrected standalone initializer build and bounded device
evidence are in `cuda-init3d-sorted/` there. Source archive SHA256 is
`a61c5e3d519f04f0f5c18a7a680c9d6ef863a0b6bd3cbd4d9d3f516f028094db`;
installed CUDA library SHA256 is
`32f63beffde96354aa95c8e451d42b49ed2ee139d31c5205e79a5cad0df586bf`.
It repeated exactly for fixed 48-row and 1,024-row KNN inputs, and a 2D
regression passed. The 1,024-row first initialization took 0.275 seconds in
this bounded check; this is not a full-pipeline performance result.
Prepared 3D CUDA optimizer evidence is in `cuda-prepared3d/` beside it.
The source archive SHA256 is
`c464739900814982c31d790a5983993f58cd750f38752221b57a981c6131a406`;
installed CUDA library SHA256 is
`76f67fb8ce43936925416666da79ddb6b15a9e5101003a0b24b86112f02c8991`.
Fuzzy and binary 48-row 3D reuse and the 2D regression passed; the
GPU context was released. This is not a larger-data quality or speed test.
The shared CUDA Louvain/Leiden graph-options regression is in
`cuda-graph-options/` beside it. Source archive SHA256 is
`11cf564c8932821eb38c3bbc973453c2d8c8bb3476a93b836f027cac3978102a`;
installed CUDA library SHA256 is
`9fe515821ff9b51e7ecfdb4a9afd68556f0e87cdaaa2575b16a58c86fa7c59d3`.
The two-A10G terminal evidence is at
`benchmarks/linux/hf-current-multigpu-20261102/evidence-20261103/`.
The Chiamaka 3D evidence is at
`benchmarks/linux/chiamaka-cuda-tsne3d-20261102/evidence-20261103/`.
Neither replaces full-dataset benchmark evidence. Silvano's 11-dataset
source-locked panel remains suspended under the user's later direction.
Nine datasets completed execution; FlowRepository is partial and ImageNet
has not started. The dependent audit is also suspended. Do not resume the
panel without a new user instruction. The postponed Deep1B 100M run
remains outside the current benchmark until the missing algorithm work is
complete.
