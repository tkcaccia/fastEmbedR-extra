# Deep1B and Turing disk-backed benchmark (experimental)

For multiple full-graph Deep1B routes under a shared SSD quota, preview
`submit_storage_budgeted.py --quota-free-bytes BYTES` first. It groups
CPU, one-GPU, and two-GPU runs into waves whose summed graph-stage bounds
fit within 80% of free quota and physical space. CPU submission also
requires `--cpu-clustering-reserve-bytes` for Leiden work, which the graph
bound excludes. Add `--submit` only after reviewing the plan. Set
`DEEP1B_BASE` for a non-default project root and
`DEEP1B_IMAGE_SHA256` to pin the image. A wave after the first starts only
when every prior-wave job succeeds; other users' jobs are not reserved by
this planner. This controls concurrent disk demand; it does not compress
the source data or the persistent symmetric CSR graph. The opt-in
`--admission initial` policy admits one-billion-row graph jobs using the
smaller initial bucket-staging bound; submission additionally requires
`--accept-late-space-failure`. A later measured-bucket check may still
stop the job. Initial-admission jobs always run one at a time to avoid
concurrent measured-bucket checks racing for the same free space. This
option is not a guaranteed reduction in peak SSD.

Combined full-graph t-SNE/UMAP runs at 100 million rows or more use the
lower-SSD strategy by default when launched with `submit_fullgraph5m.sh`.
Smaller runs share one kNN build unless
`DEEP1B_REBUILD_KNN_FOR_UMAP=1` is set explicitly.
t-SNE then consumes its package-generated kNN pair, and the runner
rebuilds the same route from the original input before UMAP. Both
exact-neighbor audits and the extra kNN time are saved separately in
`knn.csv`, `knn_rebuild.csv`, and `stages.csv`; effective HNSW settings
are saved for both builds. Set `DEEP1B_REBUILD_KNN_FOR_UMAP=0` to share
one kNN build when speed matters more than peak SSD use. This strategy does
not compress the final CSR graph or change the search algorithm; repeated
approximate searches can produce different neighbor IDs. It cannot be
used with single-method modes. A failed second build stops explicitly.
If t-SNE fails before UMAP, the runner stops without rebuilding KNN;
there is no useful second graph to construct in that failed campaign.

For Deep1B at one billion rows and k=30, the conservative combined-run
graph-stage estimate changes from 1.352 TB to 1.112 TB, plus the
existing 384 GB input and other files. It excludes Leiden work and
concurrent jobs. This is a planning bound, not a
measured one-billion-row peak; the repeated kNN build is a substantial
time cost. The two graph builds still use the exact same algorithms.
Within each consuming bucketed build, KNN rows are read from the end and
processed file tails are truncated. This lowers the initial staged-data
bound from about 632 GB to 392 GB for a one-billion-row combined run
with KNN rebuilding. It does not lower the later 1.112 TB bound.
Run `Rscript ../benchmark_streamed_knn_space.R 1000000 30` from this
directory to compare graph bytes, logical disk peaks, and elapsed time
on a generated ring KNN input without downloading Deep1B.
On a separate 100,000-row, k=30 scattered-neighbor fixture,
`benchmark_bucketed_graph_space.R` produced byte-identical CSR files
with bucketed sorting. Its measured sort payload was 76,487,260 versus
120,771,408 bytes for t-SNE, and 76,489,012 versus 120,781,328 bytes
for UMAP. These are temporary sorter payloads, not whole-job SSD peaks;
the generated KNN and final graph still require storage. The bucketed
builds took 6.214 versus 7.096 seconds for t-SNE and 6.238 versus 6.547
seconds for UMAP in this local fixture. No result here establishes a
one-billion-row measured peak or speedup.
Run `Rscript test_rebuild_knn_storage.R` from this directory for the
small consume/rebuild test. It compares all six final t-SNE and UMAP
CSR files and short optimizer outputs byte-for-byte when the exact KNN
build is reproducible; it also checks both generations were consumed.
`Rscript test_rebuild_knn_storage_hnsw.R` exercises the file-backed
faissR HNSW route on 6,000 rows and compares t-SNE graph bytes and
reported graph-stage disk peaks. In a current-source local run, the
300-row exact test reduced the reported t-SNE graph-stage peak from
72,288 to 48,288 bytes, with identical CSR files and short layouts.
The 6,000-row HNSW test reported 5,839,452 versus 4,399,452 bytes;
its sampled recall was 0.98125, below the 0.99 quality target. These
are small-fixture storage checks, not publication-scale measurements.
`test_run_full_graph_failfast.R` injects a t-SNE affinity failure and
checks that only the first KNN build was attempted.
A full 2,000-row
CPU smoke fit completed, including t-SNE, UMAP, and Leiden. On that
older smoke fit, the generated t-SNE graph-stage peak fell from
1,771,936 to 1,291,936 bytes. The first and rebuilt sampled kNN
recalls were both 1.0. Separate current-source 1,000-row runs produced
different t-SNE and UMAP coordinates despite identical PCA and Leiden
files; independent approximate builds or optimizer ordering are not
byte-reproducibility controls. These are small-test observations, not
measurements of Deep1B or whole-workspace peak SSD allocation.

The current 20M-capped Deep1B campaign and matched 1M classic comparison
are described in [README_20M.md](README_20M.md). The earlier
[full-graph rebuild](FULL_GRAPH_REBUILD_20261012.md) is superseded;
do not launch its 100M jobs.
The older `scale10m`, `boundary`, and `billion` embedding phases below
are legacy landmark projections, not full-graph fits or part of the
current 20M submission.

This lane uses the completed Yandex DEEP 1B or Microsoft Turing-ANNS file
directly. It does **not** copy prefixes or load the full matrix into R RAM.
`massive_matrix()` opens
the `.fbin` descriptor; `--first-row` selects a disk-backed row window.
The GPU routes stage bounded chunks. Prefixes and windows are reproducible
but are not representative samples of all 1B vectors.
The source and terms are recorded by the downloader; see the
[Big ANN dataset listing](https://big-ann-benchmarks.com/neurips21.html).

Input on Chiamaka/HPC:

```
/scratch/firenze/NN/Data/BigANN/deep/1000000000/base.1000000000.fbin
/scratch/firenze/NN/Data/BigANN/deep/1000000000/manifest.json
/scratch/firenze/NN/Data/BigANN/turing/1000000000/base.1000000000.fbin
/scratch/firenze/NN/Data/BigANN/turing/1000000000/manifest.json
```

Deep1B has 96 features and 384,000,000,008 bytes; Turing has 100 features
and 400,000,000,008 bytes. Both have 1,000,000,000 rows. Each input must
have a matching completed manifest and header. `.part` files are rejected.
The downloader
records a whole-file SHA-256 in the manifest. A normal launch checks that
metadata and the header without rereading 384 GB; `--verify-sha256` performs
a one-time full rehash when source integrity must be re-established.

## Experiment phases

| Phase | Rows | Runs | Purpose |
| --- | ---: | --- | --- |
| `pilot` | 20,000 | CPU/CUDA PCA, KNN, landmark UMAP/t-SNE | Functional and sampled-recall check on the full file's prefix |
| `cluster_pilot` | 20,000 | CPU Leiden/Louvain/Walktrap; CUDA Leiden/Louvain | Clustering runtime and full-output integrity gate |
| `scale` | 1 million | CPU/CUDA PCA, KNN, landmark UMAP/t-SNE; 2-GPU PCA and landmarks | Stage time, RSS, disk I/O, GPU placement |
| `cluster_scale` | 1 million | CPU/CUDA Leiden/Louvain; 2-GPU Leiden | Clustering scale and multi-GPU gate |
| `threads1m` | 1 million | PCA, full KNN, landmark UMAP/t-SNE at 2/4/8/12 CPU workers | CPU scaling with matched Slurm allocations |
| `fresh5m` | 5 million, from row 1,000,001 | CPU/CUDA PCA and landmark UMAP/t-SNE; 2-GPU PCA and landmarks | Independent-window time, RSS, and quality |
| `fresh5m_3d` | Same 5 million | CPU, 1-GPU, and 2-GPU PCA/UMAP/t-SNE with three components | Separate 3D capability and quality gate |
| `fresh5m_graph` | Same 5 million | CPU HNSW or CUDA IVF full KNN | All-row graph and sampled exact recall |
| `boundary` | 100 million | CPU/CUDA PCA and landmarks; 2-GPU PCA | Test 38.4/40 GB of selected input under an 8 GB Slurm RAM cap |
| `billion` | 1 billion | CPU, 1-GPU, and 2-GPU PCA, landmark UMAP/t-SNE, and Leiden clustering | Guarded post-100M stress test; no full 1B graph |

The next-run registry also includes Leiden/Louvain on CPU and CUDA at
20k, 1M, and 5M rows, with a CPU-only 20k Walktrap diagnostic. The
100M and 1B phases use Leiden for full-row landmark assignment. These
cases do not run in the already source-locked 5M campaign.

`pilot` and `scale` use `k=30`, 4 CPU workers, seed 4, 2 PCA components,
and 1,000 or 5,000 landmarks. `boundary` and `billion` use 10,000 landmarks.
t-SNE requests 250 early plus 750 normal optimization iterations for the
landmark fit and 250 projection iterations. The full KNN cases retain the
package's CPU HNSW-sharded or CUDA cuVS IVF-sharded route; they do not use
NN-descent. KNN recall is measured on 16 exact-reference rows in pilot/scale
and 128 in `fresh5m_graph`. It is not a guarantee for every row. A sampled
mean below 0.99 fails the new audit.

The 512-row quality sample uses the same deterministic, dispersed row IDs
for every fitting method at a given prefix size. Trustworthiness and local
neighbor preservation are measured **within that sample**, not against all
1B neighbors. Neither input has labels in this lane, so label KNN accuracy
is not reported. `metrics.csv`, `quality.csv`, `quality_row_ids.csv`,
`plot_sample.csv.gz`, `plot_sample_10000.csv.gz`,
`time.txt`, and `status.tsv` are retained per case. `metrics.csv` includes
observed process peak RSS and `/proc/self/io`; `/usr/bin/time -v` provides
an independent MaxRSS. The selected-input byte count is distinct from the
physical 384/400 GB file size. Plot/CSV output is small; no dense coordinate
CSV is written. CUDA cases also retain `gpu_memory.csv`, a sampled peak
allocation for compute processes in the fit's process tree or process
group, including reparented workers. The CSV records that attribution and
UUID-keyed per-device peaks. Sampling is a lower bound, not an exact
instantaneous device high-water mark. A two-GPU case
fails its audit unless contexts appear on two distinct devices.
The package's separate VRAM figure remains an estimate.
The quality check reads fixed rows from the final `.f32` output. No duplicate
full-layout CSV or fit-object RDS is written. The binary outputs and package
checkpoints remain available for recovery and inspection until explicitly
pruned.
Clustering cases retain `cluster_sample.csv.gz` and a compressed list
of reference landmark labels; `quality.csv` records the full-output
scan, landmark-label agreement, community count, and confidence. These
unlabeled ANN datasets cannot provide ARI or biological cluster validity.

## Reclaim result space

For a comprehensive campaign that is still running, use the guarded
per-stage cleaner below. It only offers final `.f32`/`.u32` payloads from
PASS-audited stages after every expected full-row PNG for that stage exists
and the relevant Slurm jobs are inactive. It retains metrics, quality,
timing, GPU memory observations, job ledgers, audit reports, PNGs, input
files, checkpoints, and failed/incomplete stages. Review the dry run first.

```bash
cd /scratch/firenze/NN
campaign=/scratch/firenze/NN/fastEmbedR-results/massive-data/\
comprehensive/20261010T124017Z_iyjkEW
python3 benchmark_scripts/massive-data/deep1b/\
prune_completed_payloads.py "$campaign"
python3 benchmark_scripts/massive-data/deep1b/\
prune_completed_payloads.py "$campaign" --apply
```

Only use `--apply` after the small-result copy has been checked locally.
The removed paths and byte counts are recorded in
`pruned_payloads.tsv`. Completed binary layouts cannot be re-rendered
after this cleanup. This cleaner does not delete the completed BigANN
sources or the stage output directories. Use `du -h --max-depth=2` on
`fastEmbedR-results/massive-data` to identify older campaigns separately;
do not remove an active campaign just because it is large.

For future campaigns, `visualization/render_full_layouts.R` creates
individual full-row PNGs and a 300-dpi, three-panel PCA/t-SNE/UMAP PNG
per dataset, backend, and row count when all three source stages pass.
`figure_manifest.csv` names the panel and source cases. The images use
grayscale point density, because Deep1B and Turing have no verified class
labels. They are suitable for layout inspection, not labelled-cluster
claims. Failed stages do not enter the combined figure. Run the renderer
and visual audit before pruning; old source-locked jobs do not adopt later
renderer changes automatically.

After all jobs in a campaign have finished, inspect the payload size first:

```bash
cd /scratch/firenze/NN
campaign=/scratch/firenze/NN/fastEmbedR-results/massive-data/deep1b/20261006T202230Z_pilot
bash benchmark_scripts/massive-data/deep1b/prune_campaign.sh "$campaign"
```

To remove generated `.f32`, `.u32`, `.u64`, `.rds`, and `.part` payloads from
that **specific** campaign while retaining source hashes, metrics, quality
scores, timing, and errors, repeat with `--apply`. The script refuses to run
if any job in the campaign ledger is still queued or running. It never touches
the BigANN input files. Do not prune a campaign needed for recovery, visual
inspection, or further scoring. A failed pilot with no completed output may
reclaim very little space.

## Launch on the HPC

For the new source-locked 5M manuscript rerun, use the single automatic
controller described in `../RUN_ON_HPC_20261009.md`. It runs three
non-overlapping timed repetitions by default, submits the next stage from
a short `ada` controller job after each audit, and records stage/quality
status in `state.json`. It also bundles related CPU or GPU cases in one
allocation, reducing repeated L40S queue waits. Do not replace suite
files until the currently running source-locked campaign is done. The
new ordering completes CPU-only stages before L40S-dependent work; it
does not retroactively reorder a campaign already submitted to Slurm.

The commands below describe the older independent pilot/scale launcher
and manual phase operation.

Sync this directory **and** its parent `run_scaling.R` to
`/scratch/firenze/NN/benchmark_scripts/massive-data/`. First validate the
completed input and the image:

```bash
LOCAL=/Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/massive-data
HOST=01481067@hex.uct.ac.za
REMOTE=/scratch/firenze/NN/benchmark_scripts/massive-data
rsync -av --exclude=__pycache__ "$LOCAL/deep1b/" "$HOST:$REMOTE/deep1b/"
rsync -av "$LOCAL/run_scaling.R" "$HOST:$REMOTE/run_scaling.R"
```

On the HPC:

```bash
cd /scratch/firenze/NN
python3 benchmark_scripts/massive-data/deep1b/validate_input.py \
  Data/BigANN/deep/1000000000/base.1000000000.fbin
python3 benchmark_scripts/massive-data/deep1b/validate_input.py \
  Data/BigANN/turing/1000000000/base.1000000000.fbin \
  --dataset turing
sha256sum singularity/fastembedr_cuda.sif
bash benchmark_scripts/massive-data/deep1b/submit_parallel.sh
```

The legacy launcher submits pilot and 1-million-row scale cases for
both Deep1B and Turing. CPU and CUDA jobs run independently; neither waits
for a pilot or an L40S queue. Across both datasets this is 16 pilot and 22
scale cases, including two-GPU PCA, UMAP, and t-SNE. A single dependent
audit runs after all arrays finish. There is no automatic 100-million-row
or billion-row submission.

The launcher prints an overnight ledger path. Inspect it the next day:

```bash
squeue -u "$USER"
ledger=/scratch/firenze/NN/fastEmbedR-results/massive-data/parallel/ID
cat "$ledger/stages.tsv" "$ledger/failures.tsv"
cat "$ledger/final_audit.txt" 2>/dev/null || true
```

Replace `ID` with the printed directory name. Each case retains
`status.tsv`, `metrics.csv`, `quality.csv` where applicable, and checksum
evidence. Each campaign has `audit.json`; the overnight ledger has launch
logs and per-campaign audit logs. A KNN mean recall below 0.99 fails the
per-campaign audit. The small reference sample does not prove recall for
all observations. The CUDA landmark projection cases request
`n.cores = 1`, as required by the package; CPU cases retain four workers.

The default manual launch remains Deep1B; use `submit.sh pilot turing` for
Turing alone. Turing results are stored under
`fastEmbedR-results/massive-data/turing/`, separate from Deep1B's
`fastEmbedR-results/massive-data/deep1b/`. The input, dataset identity,
image, and source checksums are saved in each campaign. Never overwrite
suite files while jobs from an earlier campaign are still pending.
Preflight now runs as an `ada` batch job, not on the login node. The
CPU/GPU arrays depend on it, and an automatic audit follows them. The
image must have the persistent faissR 0.99.52 bridge and row-view API.

Inspect every `status.tsv` and the recorded package DLL hash before moving
to the next phase. Launch phases separately; no CPU case waits for a GPU
case. The default Slurm throttle is two CPU tasks, two one-GPU tasks, and
one two-GPU task. A two-GPU case requests two L40S cards. Override with
`DEEP1B_CPU_THROTTLE`, `DEEP1B_GPU_THROTTLE`, or
`DEEP1B_GPU2_THROTTLE`, and set accounts/partitions with
`DEEP1B_CPU_ACCOUNT`, `DEEP1B_CPU_PARTITION`, `DEEP1B_GPU_ACCOUNT`, and
`DEEP1B_GPU_PARTITION`; use `DEEP1B_BASE` for another project root.
Set `FASTEMBEDR_EXPECTED_VERSION` and, when known,
`FASTEMBEDR_EXPECTED_DLL_SHA256` to reject an unintended package build.

```bash
bash benchmark_scripts/massive-data/deep1b/submit.sh scale
bash benchmark_scripts/massive-data/deep1b/submit.sh threads1m deep
bash benchmark_scripts/massive-data/deep1b/submit.sh threads1m turing
bash benchmark_scripts/massive-data/deep1b/submit.sh fresh5m deep
bash benchmark_scripts/massive-data/deep1b/submit.sh fresh5m turing
# After the 5M quality and HNSW refinement gates:
bash benchmark_scripts/massive-data/deep1b/submit.sh fresh5m_graph deep
bash benchmark_scripts/massive-data/deep1b/submit.sh fresh5m_graph turing
bash benchmark_scripts/massive-data/deep1b/submit.sh boundary
DEEP1B_ALLOW_BILLION=1 \
  bash benchmark_scripts/massive-data/deep1b/submit.sh billion
# Use the same phase names with "turing" as the second argument.
```

The last command is intentionally guarded. Its output and scratch-space
estimate must be reviewed before launch. The 8 GB Slurm memory request is
an experimental cap, not a claim that all cases will fit. The runner rejects
insufficient free output space and records nonzero exits; no CPU/GPU fallback
is permitted. A preflight does not claim that an unrun 100M or 1B case works.
The supplied image must contain the experimental row-view API and all
requested backends; an older image will fail explicitly during `pilot`.

## Small result copy and plots

The synchronized mount may expose scripts without the result tree. Run
these commands on the Mac to copy only small evidence and plot it:

```bash
bash /Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/\
massive-data/deep1b/copy_small_results.sh
Rscript /Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/\
massive-data/deep1b/plot_small_results.R \
  /Users/stefano/Documents/fastEmbedR-results/massive-data
```

The copy excludes `.fbin` input, `.f32` output, graph binaries, RDS
checkpoints, and full embedding CSVs. The plotter writes
`plots/summary.csv`, `plots/performance.pdf`, `plots/layout_samples.pdf`,
`plots/fresh5m_comparison.pdf` when 5M layouts exist,
`plots/layout_samples_3d.pdf` when 3D samples exist, and
`plots/cluster_overlays.pdf` when cluster samples exist. Layouts
show up to 10,000 dispersed rows, not all billion observations. Quality
scores use a separate 512-row sample.
At 1B rows and 30 neighbors, a saved all-row landmark neighbor sidecar
alone is about 240 GB per embedding or clustering case. The runner
checks a conservative scratch-space allowance before starting; the
small-result copy never transfers these sidecars.

## Extended automatic run

After the original automatic 5M campaign finishes auditing, sync the
updated suite and run one command on the HPC:

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/massive-data/deep1b/submit_extended.sh \
  /scratch/firenze/NN/fastEmbedR-results/massive-data/automatic/\
20261009T070305Z_e3s9V2
```

This queues independent CPU and CUDA lanes. Each runs Deep and Turing
through 20k and 1M clustering checks, 5M 3D outputs, then 100M and 1B
file-backed stress tests, advancing only when its own audit passes.
Ada never depends on L40S. Do not sync new suite files while the original
source-locked campaign is active. Simultaneous lanes can contend for disk
I/O, so the extended run is a correctness and resource stress test;
publication timings require separate, uncontended repetitions.

## What this does not establish

This lane does not run a **full 1B KNN graph** or a full 1B UMAP/t-SNE
optimizer. The largest cases use landmark projection, which still writes one
result per observation. Multi-GPU cases test distributed PCA moments or
landmark projection, not multi-GPU full-graph optimization. A separately
scoped checkpoint/interruption test is needed before claiming recovery at
100M/1B rows. Repeated fixed-seed timings, full-dataset quality metrics,
and comparisons with other implementations remain separate experiments.
