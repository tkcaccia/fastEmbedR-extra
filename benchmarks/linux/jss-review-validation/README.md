# fastEmbedR JSS reviewer-validation suite

This directory prepares the release-level calculations requested during the
JSS review. It does not submit jobs by itself. The only submission entry point
is `submit_all.sh`, which the user runs explicitly on the HPC.

## Fixed paths

- HPC root: `/scratch/firenze/NN`
- image: `/scratch/firenze/NN/singularity/fastembedr_cuda.sif`
- datasets: `/scratch/firenze/NN/Data`
- shared inputs: `/scratch/firenze/NN/fastEmbedR-input/jss_validation`
- results: `/scratch/firenze/NN/fastEmbedR-results/jss_validation`
- logs: `/scratch/firenze/NN/benchmark_logs`

The scripts require fastEmbedR 0.1 by default. Override this only when a new
release is deliberately frozen:

```bash
EXPECTED_VERSION=0.1 bash \
  benchmark_scripts/fastembedr_jss_review_validation/submit_all.sh
```

Every CUDA job fails explicitly when a native component required by that
experiment is unavailable. The strict preflight executes real CUDA UMAP, PCA,
and Leiden calculations and verifies their returned backend metadata. There is
no CPU fallback.

## Experiments

1. `precompute`: selects at most 70,000 observations per dataset with a fixed
   stratified row set, then saves one CPU KNN object at width 90, one two-column
   t-SNE PCA initialization, and one fixed quality sample. These objects are
   reused by CPU and CUDA support experiments.
2. `affinity`: characterizes conditional t-SNE affinities at perplexities
   5, 15, 30, and 50 with support multipliers 1, 2, 3, and 4. It reports
   achieved perplexity, normalized entropy, probability dispersion,
   nearest-to-farthest weight ratio, local mass, beta, and search iterations.
3. `support`: compares production compact support (`k = P`) with a diagnostic
   conventional support (`k = 3P`) using identical KNN candidates, PCA
   initialization, optimizer schedule, seeds, and backend. It performs one
   warm-up, five same-seed timing repetitions, and seeds 4, 17, and 29. The
   fixed quality sample is used for trustworthiness, Preserve@30,
   embedding-space label KNN accuracy, and sampled common-affinity KL.
4. `transform`: evaluates genuinely unseen 20% query observations for fuzzy
   UMAP and compact-support t-SNE. It records reference-fit time, query
   transform time, joint-embedding time, query-to-reference neighborhood
   preservation, label accuracy, Procrustes similarity to joint embedding,
   and verifies zero displacement of fixed reference coordinates. HPC jobs
   cover CPU and CUDA on every dataset; `local/run_transform_metal.sh` applies
   the identical experiment to Metal using the same archived row sets.
5. `landmark_reconstruction`: selects a fixed 20% landmark reference and
   reconstructs the omitted 80% from that reference. It validates standard
   fuzzy UMAP and compact-support t-SNE separately on CPU, CUDA, and Metal,
   compares each reconstruction with a full joint embedding, and reports
   runtime, fixed-reference displacement, quality metrics, Procrustes
   similarity, and layout-neighborhood agreement. Reference points are drawn
   in light gray and projected points are colored by the benchmark labels.
6. `scaling`: measures CPU strong scaling at 1, 2, 4, 8, and 12 threads for
   KNN, PCA, compact-support t-SNE optimization, and fuzzy UMAP optimization
   on COIL20, MNIST, full flow18, and 100,000 ImageNet rows. Each thread count
   is submitted through a separate Slurm array with one task and a matching
   `cpus-per-task` request. The 32 GB memory request avoids converting a small
   thread-count experiment into a large CPU allocation under memory-per-CPU
   accounting.
7. `pca`: requests PCA ranks 2 and 50 on every dataset. A requested rank is
   reduced to `min(rank, n - 1, p - 1)` when necessary because randomized
   singular value decomposition requires a rank strictly below both matrix
   dimensions. CPU uses 1, 4, and 12 threads; CUDA uses its native backend.
   `irlba` is timed only as an
   approximate performance comparator, never as an exact reference.
   `pca_accuracy` is a separate, untimed-for-headline-evidence experiment on
   fixed tractable subsets. It compares CPU, Metal, and CUDA scores, loadings,
   singular values, captured variance, and reconstruction error with a dense
   centered singular value decomposition. It also reports direct matched
   score- and loading-space agreement between backends. Keeping this work in a
   separate process prevents the dense reference and double-precision copy
   from contaminating PCA runtime or memory measurements.
8. `clustering`: precomputes one shared-nearest-neighbor graph per dataset and
   reuses it for every method, seed, and backend. CPU Louvain, Leiden, and
   Walktrap are compared with the corresponding `igraph` implementation.
   CUDA Louvain and Leiden use the identical graph and are compared with the
   CPU native memberships. Outputs include runtime, modularity, community
   count, label adjusted Rand index, reference-membership adjusted Rand index,
   and the Leiden connected-community diagnostic. Walktrap uses a fixed
   stratified subset of at most 1,500 rows; Louvain and Leiden use at most
   10,000 rows. The graph-build time is reported separately and excluded from
   clustering runtime.
9. `knn_observed`: audits the nearest-neighbor search used by each complete
   embedding workflow. It runs the public `precompute_knn()` policy on each
   complete benchmark matrix, compares fixed sampled query rows with exact
   neighbors from that full matrix, and reports mean, median, fifth-percentile,
   and minimum recall together with the actual engine, exact/approximate flag,
   target recall, and HNSW or IVF tuning parameters. Search, host-transfer, and
   exact-reference times are diagnostic and excluded from runtime claims.
10. `knn_sensitivity`: records observed recall@30 on fixed sampled references.
   A 0.90, 0.95, and 0.99 target sweep is run only when the sampled CUDA
   workload actually selects IVF-Flat. Small CUDA workloads use the production
   exact route once and record recall 1.0; CPU HNSW is also run once because
   its release policy does not expose a recall-target sweep. Exact-reference
   recall uses fixed sampled queries rather than a dense all-pairs R matrix.
   PCA initialization uses the requested backend. Stage progress is printed so
   KNN, reference, PCA, t-SNE, and UMAP time cannot be confused.
11. `component_validation`: runs exact-force, finite-difference, FFT-grid,
   float32-versus-float64, one-step, trajectory, support-sweep, and
   pathological-input checks from the source-frozen numerical validator.
12. `tsne_longrun`: directly addresses final-trajectory agreement. Four fixed
   stratified inputs of at most 2,000 observations are saved with exact compact
   KNN support, compact affinities, source row identifiers, and seed-specific
   PCA initializations. CPU, CUDA, Metal, and Python openTSNE then use those
   same inputs, 250 early-exaggeration iterations, fixed learning rate,
   momentum, clipping, and independent normal-phase checkpoints at 50, 100,
   250, 500, 750, and 1,000 iterations. The native runs sweep FFT grids 128,
   256, and 512. Final grid-256 runs use seeds 4, 17, and 42; CPU also checks
   1, 4, and 12 threads. Outputs include common-affinity KL, native KL,
   trustworthiness, Preserve@30, label KNN accuracy, layouts, objective traces,
   Procrustes agreement, and layout-neighborhood agreement. Python fit-only
   timing is labelled separately and is used here as a numerical reference,
   not mixed into workflow-level speed claims. The trajectory and seed runs
   are correctness runs: their single elapsed values are marked ineligible for
   runtime claims. A separate timing family performs one excluded warm-up and
   five fixed-seed repetitions for CPU and Python, and ten for CUDA because
   short accelerator runs require more repetition.
13. `backend_quality`: provides dataset-level CPU, CUDA, and Metal quality
    evidence for compact-support t-SNE and fuzzy UMAP. `matched_knn` runs reuse
    the identical host KNN object, PCA initialization, sampled observations,
    and seeds across backends. `full_workflow` runs each public backend pipeline
    on the same observations while retaining the same optimizer controls.
    Every row reports trustworthiness, Preserve@30, label KNN accuracy, and,
    for t-SNE, the recorded final KL divergence and sampled compact-affinity
    KL. Complete workflows retain the KNN object generated inside that exact
    embedding call after timing has ended. Its sampled rows are compared with
    the fixed full-matrix exact reference, so observed recall appears directly
    beside embedding quality. Elapsed values from these quality runs are
    explicitly ineligible for runtime claims.

All eleven datasets are included: COIL20, USPS, FashionMNIST,
FlowRepository_FR-FCM-ZYRM_files, flow18, MNIST, ImageNet features, MetRef,
mass41, Tabula Muris, and Macosko2015 retina.

## Timing and memory boundaries

- A returned host layout is produced only after the native CUDA implementation
  synchronizes the device, so the elapsed timer includes completed GPU work.
- `/usr/bin/time -v` records task peak resident set size.
- CUDA jobs sample device memory every 0.2 seconds and retain both the raw GPU
  memory and the increment above the pre-run allocator baseline.
- The support experiment separates repeated timing at seed 4 from independent
  embedding seeds. The warm-up run is never included in timing summaries.
- Timing summaries never use one run per seed as timing replicates. They report
  the median and interquartile range of same-seed repetitions after warm-up;
  seed variation remains in separate quality and stability files.
- Missing, unavailable, failed, and timed-out Slurm tasks remain explicit in
  status files and scheduler accounting; no zero or artificial bar is created.
- CPU launchers request one Slurm task and set `cpus-per-task` to the worker
  count used by R. Variable-thread scaling and PCA experiments use separate
  arrays for each worker count. Their 32 GB request is supported by the
  measured peaks from the preliminary campaign and avoids memory-driven CPU
  inflation on clusters that account memory per CPU. Each worker refuses to
  start if its requested R thread count exceeds `SLURM_CPUS_PER_TASK`. The
  complete observed-recall worker requests 128 GB because the full ImageNet
  reference calculation exceeded 32 GB.
- Most CUDA launchers request one L40S GPU, one Slurm task, four host CPUs, and
  64 GB of host memory. The complete observed-recall worker requests 128 GB.
  Their array throttle is five, while the current account association allows
  four L40S GPUs; Slurm enforces the lower limit. Clustering requests three host
  CPUs and uses an explicit four-task throttle, matching the 12-CPU and
  four-GPU association limits. Slurm may run fewer tasks when physical GPUs or
  shared-account resources are unavailable.

## Submit

The recommended launcher is a staged, self-submitting Slurm controller. It
submits one bounded wave at a time, waits through Slurm dependencies rather
than polling, retries submission-limit errors every 60 seconds, and records
every job in a campaign-specific `jobs.tsv`. Every wave advances through
`afterany`, allowing independent calculations and the final audit to record
partial failures without leaving mutually unsatisfied controller branches.

After both preflights pass, start the complete campaign with one command:

```bash
cd /scratch/firenze/NN
bash \
  benchmark_scripts/fastembedr_jss_review_validation/submit_complete_campaign.sh
```

Each launch creates an isolated directory below
`fastEmbedR-results/jss_validation/campaigns/`. Its `campaign_manifest.txt`
records the image and installed fastEmbedR binary checksums, `jobs.tsv`
records the submission graph, and `final_audit.txt` is `PASS` only when all
worker jobs and required aggregate outputs succeed. No manual waiting or
polling is required. The launcher verifies `FILES.sha256`, copies that source
manifest into the campaign directory, and records its own SHA-256 so a campaign
cannot silently mix launcher revisions. It also checks that each Slurm worker
reserves at least the host CPUs required by its R thread setting. Do not launch
`submit_all.sh` on an
account with a small queued-job limit.

First inspect the scripts, image, and expected version. Then run:

```bash
cd /scratch/firenze/NN
bash \
  benchmark_scripts/fastembedr_jss_review_validation/submit_complete_campaign.sh
```

The older `submit_all.sh` launcher remains disabled by default because it can
exceed the cluster submission limit.

For the observed-recall and backend-quality families on an account with a
small queued-job limit, use the compact launcher:

```bash
cd /scratch/firenze/NN
bash \
  benchmark_scripts/fastembedr_jss_review_validation/submit_recall_quality_compact.sh
```

It submits 11 dataset tasks per backend. Within each task, observed KNN recall
is measured once and the 12 boundary, method, and seed quality configurations
run sequentially. A failed subrun is recorded without preventing later
configurations for that dataset from running. The aggregate uses `afterany` so
partial evidence is retained.

To submit one family manually:

```bash
sbatch benchmark_scripts/fastembedr_jss_review_validation/slurm/run_support_cpu4.sh
sbatch benchmark_scripts/fastembedr_jss_review_validation/slurm/run_support_cuda.sh
```

PCA and clustering are included automatically in the complete staged campaign.
For a focused clustering validation, preserve the graph dependency order:

```bash
CPU_PREFLIGHT_JOB=$(sbatch --parsable \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_preflight_cpu.sh)
CUDA_PREFLIGHT_JOB=$(sbatch --parsable \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_preflight_cuda.sh)
GRAPH_JOB=$(sbatch --parsable \
  --dependency="afterok:$CPU_PREFLIGHT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_clustering_precompute_cpu4.sh)
CPU_CLUSTER_JOB=$(sbatch --parsable \
  --dependency="afterok:$GRAPH_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_clustering_cpu4.sh)
sbatch --dependency="afterok:$CPU_CLUSTER_JOB:$CUDA_PREFLIGHT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_clustering_cuda.sh
```

This order ensures that every method reuses the same serialized graph and that
CUDA membership agreement is evaluated against the completed CPU results.

Held-out transformation and landmark reconstruction can be submitted without
the other experiment families after shared precomputation succeeds:

```bash
CPU_PREFLIGHT_JOB=$(sbatch --parsable \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_preflight_cpu.sh)
CUDA_PREFLIGHT_JOB=$(sbatch --parsable \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_preflight_cuda.sh)
PRECOMPUTE_JOB=$(sbatch --parsable --dependency="afterok:$CPU_PREFLIGHT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_precompute_cpu12.sh)
sbatch --dependency="afterok:$PRECOMPUTE_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_transform_cpu4.sh
sbatch --dependency="afterok:$PRECOMPUTE_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_landmark_reconstruction_cpu4.sh
sbatch --dependency="afterok:$PRECOMPUTE_JOB:$CUDA_PREFLIGHT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_transform_cuda.sh
sbatch --dependency="afterok:$PRECOMPUTE_JOB:$CUDA_PREFLIGHT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_landmark_reconstruction_cuda.sh
```

The CUDA launchers still fail explicitly if preflight detects an unavailable
native CUDA backend. Metal is run locally from the same shared-input archive:

```bash
bash benchmark_scripts/fastembedr_jss_review_validation/local/run_transform_metal.sh
bash benchmark_scripts/fastembedr_jss_review_validation/local/run_landmark_reconstruction_metal.sh
bash benchmark_scripts/fastembedr_jss_review_validation/local/run_pca_accuracy_metal.sh
bash benchmark_scripts/fastembedr_jss_review_validation/local/run_knn_observed_metal.sh
```

The long-run t-SNE jobs must follow their shared-input job:

```bash
INPUT_JOB=$(sbatch --parsable \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_longrun_precompute_cpu12.sh)
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_longrun_cpu4.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_longrun_final_cpu4.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_longrun_threads_cpu12.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_longrun_python_cpu4.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_longrun_cuda.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_longrun_final_cuda.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_timing_cpu4.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_timing_python_cpu4.sh
```

The CUDA timing job also depends on successful CUDA preflight. `submit_all.sh`
sets this dependency automatically. Timing outputs are written separately as
`tsne_timing_raw.csv` and `tsne_timing_summary.csv`; neither is inferred from
the correctness-seed runs.

CPU and CUDA backend-quality jobs are submitted by `submit_all.sh`. After the
shared `matched_inputs.rds` files have been copied from the HPC, run Metal on
the Mac with:

```bash
bash benchmark_scripts/fastembedr_jss_review_validation/local/run_backend_quality_metal.sh
```

The Metal launcher stops when a shared input is absent. It never regenerates a
different sample or KNN object. Aggregation writes `backend_quality_raw.csv`
and `backend_quality_summary.csv`, retaining dataset, method, backend,
boundary, seed count, median, and interquartile range. It also writes
`knn_observed_recall.csv`, `full_workflow_quality_with_knn_recall.csv`, and
`full_workflow_quality_summary_with_knn_recall.csv`, so measured recall for the
actual search route accompanies every complete-workflow quality result.

Metal is run locally only after the exact archived inputs have been copied from
the HPC. The launcher refuses to recompute them silently:

```bash
bash benchmark_scripts/fastembedr_jss_review_validation/local/run_tsne_longrun_metal.sh
```

## Evidence retained

Each task writes a status CSV, raw repetition rows, saved layouts or compact
fit summaries where applicable, `/usr/bin/time -v` output, CUDA memory traces,
and the Slurm stdout/stderr log. Preflight also records package and image
identity, the loaded shared-object checksum, backend capabilities,
`sessionInfo()`, and `nvidia-smi` output.

Metal is not runnable on the Linux HPC. The same R driver can be used for a
separate local Apple Silicon campaign, but Metal evidence must not be inferred
from these CPU/CUDA jobs.
