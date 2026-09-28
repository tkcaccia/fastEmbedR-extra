# fastEmbedR JSS reviewer-validation suite

## Campaign identity and progress

`submit_complete_campaign.sh` prints the verified fastEmbedR version,
container SHA-256, installed package DLL SHA-256, and benchmark-suite
manifest SHA-256 before returning. It saves these identities in
`campaign_manifest.txt` in the new campaign directory. The exact package
source commit is not inferred from the version; the binary and image hashes
identify what was tested.

`stages.tsv` records stage starts, submissions, and completions.
`failures.tsv` records non-successful Slurm workers and array tasks after
each wave finishes, including the stage, job ID, state, and exit code.
The controller's own submission failures are recorded there too. The strict
final check writes `job_audit.tsv`, `output_audit.txt`, and `final_audit.txt`.
An empty `failures.tsv` before the final audit means no failure has been
observed yet, not that the whole campaign has passed.

## Live CUDA comparison

Immediately after shared inputs are ready, the first GPU wave runs paired
fastEmbedR and cuML t-SNE and UMAP workflows. Small datasets are scheduled
first. Each dataset task writes a t-SNE comparison as soon as both t-SNE
methods finish, then writes a UMAP comparison as soon as both UMAP methods
finish. The rest of the campaign does not need to finish before these files
can be inspected. CUDA PCA runs later and the embedding methods are not
repeated in that stage.

For each dataset and method family, inspect
`results/cuda_comparison_live/DATASET/FAMILY/comparison.png` and
`comparison.csv`. The two panels show every fitted benchmark row with the
same label palette. Their captions give the plotted row count separately
from the fixed quality-sample count used for trustworthiness, Preserve@30,
and sampled compact-affinity KL for t-SNE. This common KL diagnostic is not
cuML's fitted objective. Each method also retains its full-resolution
`embedding.png`, `embedding.csv`, timing repetitions, and status under
`results/workflow_comparators/{r_cuda,python_cuda}/DATASET/METHOD/`.
An incomplete pair is visibly marked and fails the final audit.

The fastEmbedR time is an R public-call measurement; the cuML time is a
direct-Python fit measurement. Their input/output boundary is recorded, but
the initialization, affinity support, and UMAP policies can differ. The live
comparison is diagnostic, not a parameter-matched optimizer speedup.

```bash
cd /scratch/firenze/NN
CAMPAIGN_ID=YOUR_CAMPAIGN_ID
ROOT="fastEmbedR-results/jss_validation/campaigns/$CAMPAIGN_ID/results"
find "$ROOT/cuda_comparison_live" -name comparison.png -print | sort
find "$ROOT/cuda_comparison_live" -name comparison.csv -print | sort
```

After launch, inspect the paths printed by the launcher. For example:

```bash
tail -n 20 /scratch/firenze/NN/fastEmbedR-results/jss_validation/\
campaigns/CAMPAIGN_ID/stages.tsv
cat /scratch/firenze/NN/fastEmbedR-results/jss_validation/\
campaigns/CAMPAIGN_ID/failures.tsv
```

## Three-dimensional embedding lane

`submit_3d.sh` runs a separate 3D comparison over all 11 datasets using
the shared inputs from a completed campaign. It does not replace or overwrite
the 2D workflow comparisons. CPU R methods include fastEmbedR t-SNE and UMAP,
Rtsne, FIt-SNE in Barnes-Hut mode, uwot, and the R umap package. Python CPU
methods include scikit-learn t-SNE, openTSNE with its 3D Barnes-Hut optimizer,
and umap-learn. cuML UMAP is scheduled on CUDA. cuML t-SNE and the current
fastEmbedR CUDA optimizers are recorded as unsupported for 3D; no 2D output
is relabelled as a 3D result and no CPU fallback is permitted.

Every successful method writes `result.csv`, timing repetitions,
`embedding.csv` with three coordinates, fixed-sample quality metrics, and a
consistent fixed-angle projection PNG. The original three coordinates remain
in the CSV and are used for quality scoring. A final audit writes
`workflow_comparators_3d/audit.csv` and `metrics.csv`, failing if a result is
missing or unexpectedly unsuccessful. The GPU arrays run in two waves to stay
within the account's submission limit.

After synchronizing this suite and rebuilding the image with the 3D FFT route,
set `INPUT_ROOT` to the completed campaign's `input` directory and run:

```bash
cd /scratch/firenze/NN
export INPUT_ROOT=/scratch/firenze/NN/fastEmbedR-results/jss_validation/campaigns/CAMPAIGN_ID/input
bash benchmark_scripts/fastembedr_jss_review_validation/submit_3d.sh
```

The launcher verifies CPU/CUDA preflight evidence against the current image
hash and checks that the 3D FFT diagnostic symbol is present. It submits only
when these checks and the shared R/Python inputs are present.

This directory prepares the release-level calculations requested during the
JSS review. It does not submit jobs by itself. The user explicitly runs
`submit_all.sh` for the primary campaign or `submit_3d.sh` for this 3D lane.

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

The optional `fft_grid_sweep` fits full COIL20, MNIST, and Retina datasets
with the same CPU KNN graph, PCA initialization, seed, and 1,000-iteration
schedule at 128, 256, and 512 cells. CPU4 and CUDA jobs are separate. Each
grid saves all layout coordinates, a dot-only plot, sampled trustworthiness,
Preserve@30, label KNN accuracy, KL, one warm-up fit, and repeated embedding
times. The fixed 2,000-row quality sample is archived. The resolution score
is `1 - min(1, relative repulsive-force L2 error)` against exact forces on
that sample's final coordinates. Separately, a quality-stability score
compares trustworthiness, Preserve@30, and KL with the 512-cell fit; drops
over 0.01, 0.03, or 5% respectively trigger `review_quality`. Neither score
is a guarantee of visual quality. Peak job RSS and CUDA
memory are in the corresponding `measurement/fft_grid_sweep` files. Use a
rebuilt image after changing the package's automatic grid policy.

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
14. `workflow_comparators`: runs R CPU and fastEmbedR CUDA workflows alongside
    direct-Python CPU and direct-Python CUDA fits. R methods include
    fastEmbedR PCA, t-SNE, and fuzzy UMAP; `irlba`, `Rtsne`, FIt-SNE, `uwot`,
    and R `umap`. Dense `stats::prcomp()` timing is restricted to USPS and
    MetRef because it is an exact reference rather than a scalable
    workflow competitor. The separate bounded PCA-accuracy experiment retains
    a dense reference for every dataset and backend. Python methods include
    randomized scikit-learn PCA, scikit-learn t-SNE, openTSNE, umap-learn, and
    RAPIDS cuML PCA, t-SNE, and UMAP. One warm-up is excluded before five
    same-seed repetitions. Comparative t-SNE runs use 250 early-exaggeration
    and 750 normal iterations, matching cuML's 1,000 total iterations. The result
    records median and interquartile timing,
    fixed-row trustworthiness, Preserve@30, label KNN accuracy, sampled
    compact-affinity KL for t-SNE, PCA reconstruction error and retained
    variance, peak host resident set size, and sampled GPU memory. R and
    direct-Python timing scopes remain distinct; a separate boundary
    field records their common host-float32-input to host-result contract.
    Every result also records initialization, whether methods share exact
    initial coordinates or only the same PCA/spectral policy, PCA
    preprocessing, learning-rate policy, exaggeration, momentum, affinity
    support, optimizer, UMAP epochs, minimum distance, spread, repulsion, and
    negative-sample rate. PCA layout initialization is requested explicitly
    for fastEmbedR, FIt-SNE, Python openTSNE, scikit-learn, and cuML t-SNE.
    `Rtsne(pca = TRUE)` is recorded separately as PCA preprocessing because
    its layout remains randomly initialized when `Y_init` is absent. UMAP
    comparators explicitly request spectral initialization. The aggregate
    `workflow_comparator_parameters.csv` is the machine-readable parameter
    contract. Each dataset has one portable float32 input shared by every
    Python method. fastEmbedR results retain per-repetition preprocessing,
    KNN, initialization, and embedding stage timings when the returned fit
    reports them. Paired CUDA embedding jobs and independent CPU validation
    waves start after shared comparator inputs. R CPU, Python CPU, and CUDA
    PCA jobs follow their respective lanes. Aggregation waits for every
    comparator result.

The backend-quality experiment is an accuracy diagnostic. Its elapsed value is
stored as `elapsed_sec_diagnostic`, uses no excluded warm-up, and always has
`timing_eligible = FALSE`. It cannot enter a speed ratio. Publication timing
comes only from the workflow-comparator rows with one excluded warm-up, at
least five same-seed repetitions, a synchronized returned result, and the
declared iteration contract. Separate CUDA t-SNE and UMAP comparison files
are created only after matching dataset, row count, precision, output
dimensions, seed, and input/output boundary. R and direct-Python timing scopes
remain separately labelled. These are workflow comparisons under reported
package settings, not parameter-matched optimizer comparisons: t-SNE affinity
support and UMAP minimum-distance policies differ. The final audit requires
all eleven pairs, finite stage timings and quality values, and passing
method-specific status rows. `validate_benchmark_logic.R` checks pairing and
duplicate-row trustworthiness before a campaign is submitted.

The full-dataset cuVS KNN experiment and the 70,000-row-capped quality
experiment are different workloads. Their elapsed values are never divided
or presented as components of the same timed call. The workflow-comparator
stage timing reports KNN cost inside the same full public call.

All eleven datasets are included: COIL20, USPS, FashionMNIST,
FlowRepository_FR-FCM-ZYRM_files, flow18, MNIST, ImageNet features, MetRef,
mass41, Tabula Muris, and Macosko2015 retina.

## Publication-image comparator contract

The complete campaign begins with executable comparator preflights. The image
must contain R packages `fastEmbedR`, `float`, `irlba`, `Rtsne`, `uwot`, and
`umap`; the FIt-SNE R wrapper and executable at `/opt/fit-sne/bin`; and Python
packages scikit-learn, openTSNE, umap-learn, CuPy, and RAPIDS cuML. The CPU
preflight runs a finite smoke calculation with every R comparator. The CUDA
preflight executes both fastEmbedR and cuML PCA, UMAP, and t-SNE on the
allocated GPU and synchronizes it. Namespace presence alone is not accepted
as evidence. The CPU preflight also uses production arguments and the full
CSV-output path for FIt-SNE, both `uwot` modes, and `stats::prcomp()`.

GNU `time` is recommended but no longer mandatory. Its absence must not abort
a scientific calculation; the wrapper records Slurm MaxRSS when available and
labels the measurement source. Comparator preflight jobs use `afterok`, so a
missing or nonfunctional implementation stops the campaign before expensive
input and benchmark waves are submitted.

## Timing and memory boundaries

- A returned host layout is produced only after the native CUDA implementation
  synchronizes the device, so the elapsed timer includes completed GPU work.
- GNU `time -v` records task peak resident set size when available. On a
  heterogeneous Slurm node without GNU `time`, the worker still runs and
  records `sstat` peak RSS with `measurement_source = slurm_sstat`. If neither
  source exists, peak RSS is explicitly unavailable rather than aborting the
  calculation.
- CUDA jobs sample device memory every 0.2 seconds and retain both the raw GPU
  memory and the increment above the pre-run allocator baseline.
- The support experiment separates repeated timing at seed 4 from independent
  embedding seeds. The warm-up run is never included in timing summaries.
- Timing summaries never use one run per seed as timing replicates. They report
  the median and interquartile range of same-seed repetitions after warm-up;
  seed variation remains in separate quality and stability files.
- Missing, unavailable, failed, and timed-out Slurm tasks remain explicit in
  status files and scheduler accounting; no zero or artificial bar is created.
- Comparator peak host memory covers the complete isolated worker, including
  input loading, the excluded warm-up, repetitions, and quality calculation.
  It is deliberately not presented as fit-only memory. GPU sampling uses the
  same baseline-adjusted protocol as the native CUDA experiments.
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
submits bounded waves, waits through Slurm dependencies rather than polling,
retries submission-limit errors every 60 seconds, and records every job in a
campaign-specific `jobs.tsv`. Comparator preflight advances through `afterok`.
After shared inputs are ready, separate CPU and CUDA controller lanes progress
independently. An L40S queue therefore does not delay unrelated ada work.
CUDA clustering waits until the CPU graph and membership results are ready;
aggregation starts only after both lanes and CUDA clustering finish. Later
waves use `afterany` so the final audit can record partial failures. The
full-dataset CUDA-pair campaign retains its necessary dependency: scoring
the paired embeddings must wait for the GPU fits that produce them.

After installing a rebuilt image, use the image handoff launcher. It submits
fresh strict CPU and CUDA package preflights and schedules a small `afterany`
verification job. The verification job reports either preflight failure and
starts the staged campaign only when both pass:

```bash
cd /scratch/firenze/NN
bash \
  benchmark_scripts/fastembedr_jss_review_validation/submit_after_new_image.sh
```

Do not also run the manual preflight and campaign commands below after using
the handoff launcher; doing so would create duplicate campaigns.

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
manifest into the campaign directory, and exports its SHA-256 to every worker
and controller. Each job verifies both the manifest identity and every listed
file before running, so a campaign cannot silently mix source revisions. It
also checks that each Slurm worker reserves at least the host CPUs required by
its R thread setting. Only manifest-listed scripts are checked; older scripts
left by synchronization are not part of the campaign and must not be submitted.
The staged CUDA lane bundles transformation with landmark reconstruction,
PCA timing with PCA accuracy, and the 18 long-run t-SNE settings with final
fits and timing. Each dataset gets one allocation per bundle. Every subrun
retains its original measurement, scheduler status, and output directory;
the bundle also writes a per-subrun status CSV. A failure does not skip later
subruns, but makes the array task and final audit fail. The focused full-data
fastEmbedR-versus-cuML campaign is unchanged. Do not replace the scripts in
an active campaign: its source checksum must remain fixed until completion.
Do not launch
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

## Full-source CUDA comparison

The focused fastEmbedR-versus-cuML campaign fits t-SNE and UMAP to every row
of each original dataset. It does not apply the 70,000-row cap used in the
broader validation campaign. Both t-SNE methods use 1,000 total iterations;
cuML t-SNE requests 91 neighbors, PCA initialization, and a fixed learning
rate of 200. Its gradient stopping threshold is set to zero so that all
1,000 requested iterations run; an unexpectedly early stop fails the task.
Adaptive cuML tuning is disabled because it can change the requested
neighbor count and perplexity. UMAP retains spectral
initialization. The input, fit, timing, and
full embedding CSV are saved before quality is calculated. A later R stage
scores the saved coordinates on the same fixed, stratified quality rows for
both implementations. Only quality evaluation is sampled; fitting and plots
use all source rows.

After transferring this entire checksum-locked suite to the HPC, verify that
the current image has passing CPU and CUDA preflight evidence. Launch only
this focused campaign with:

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/fastembedr_jss_review_validation/verify_preflight.sh
bash \
  benchmark_scripts/fastembedr_jss_review_validation/submit_full_cuda_campaign.sh
```

The staged controller submits 11 CPU input jobs, 11 binary-input jobs, 44
single-method GPU jobs (two concurrent), 11 R quality jobs, then a strict
audit. The four GPU methods are `fastembedr_tsne`, `cuml_tsne`,
`fastembedr_umap`, and `cuml_umap`. Each method has one warm-up and three
same-seed timed repetitions. GPU work has a 42-hour method limit and a
48-hour Slurm limit. A timeout or unavailable method is reported as a
failure, never replaced by a smaller dataset or CPU fallback.

To include NOMAD as a separate 2D CUDA method in a new full-dataset
campaign, first build an image with CUDA-enabled PyTorch and
`nomad-projection` installed from a pinned 40-character Git commit. Then
verify the new image with fresh strict CPU and CUDA preflights and run:

```bash
cd /scratch/firenze/NN
INCLUDE_NOMAD=TRUE bash \
  benchmark_scripts/fastembedr_jss_review_validation/submit_full_cuda_campaign.sh
```

The launcher uses `/opt/nomad/bin/python` for NOMAD and rejects an image
without installed, source-pinned NOMAD. A local Git checkout is accepted only
when the installed projection module matches that pinned checkout.
It records the installed NOMAD version and commit. An additional GPU wave runs
NOMAD on all source rows after the fastEmbedR/cuML pairs. The same saved
float32 input and fixed quality rows are used. NOMAD is not t-SNE or UMAP:
its inner-product neighbor search, contrastive objective, and 100-epoch
schedule are reported separately. The benchmark requests eight neighbors,
10,000 noise samples, a batch of at most 8,192 observations, and one cell
below 5,000 rows or five cells otherwise. These explicit batch and cell
settings avoid a zero-step run on small datasets. The R quality pass scores
trustworthiness, Preserve@30, and label KNN accuracy; t-SNE KL is
inapplicable. Its own `embedding.csv`, R-style `embedding.png`, timing
repetitions, host/GPU memory measurements, and status are stored at
`results/workflow_comparators/python_cuda/DATASET/nomad/`. The strict
final audit requires all NOMAD outputs when this option is enabled.
Do not include NOMAD in t-SNE/UMAP speedup ratios or treat its 100 epochs
as equivalent to 1,000 t-SNE iterations.

The launcher prints the campaign path. Its `campaign_manifest.txt` records
the image, package binary, suite checksum, and execution mode. `stages.tsv`,
`failures.tsv`, and `jobs.tsv` track progress and every job. Per-method
`result.csv`, `timing_repetitions.csv`, `embedding.csv`, `embedding.png`,
`status.csv`, `quality.csv`, and `result_with_quality.csv` live under
`results/workflow_comparators/{r_cuda,python_cuda}/DATASET/METHOD/`.
R-generated paired plots and summaries live under
`results/cuda_comparison_live/DATASET/{tsne,umap}/`. The final audit verifies
that each fit used every source row and that post-fit R quality succeeded.
Do not use incomplete results as manuscript evidence.

The cuML t-SNE failure analysis is kept in
`diagnostics/diagnose_cuml_tsne.py`. It compares the archived adaptive
750-iteration setting with 1,000-iteration adaptive and fixed-parameter
settings on the same MetRef float32 matrix. Random initialization is only a
diagnostic control; the published comparison uses PCA initialization.
The MetRef diagnostic showed that cuML's default `min_grad_norm=1e-7`
stopped its FFT route at 28 iterations with a collapsed layout. Setting
`min_grad_norm=0` completed 1,000 iterations. The current HPC campaign is
checksum-locked and must not be changed in place; this policy is for the
next campaign after the revised suite is transferred.

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
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_transform_landmark_cuda_bundle.sh
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
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_longrun_cuda_bundle.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_timing_cpu4.sh
sbatch --dependency="afterok:$INPUT_JOB" \
  benchmark_scripts/fastembedr_jss_review_validation/slurm/run_tsne_timing_python_cpu4.sh
```

The bundled CUDA job also depends on successful CUDA preflight. Timing outputs
are written separately as
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

Each successful workflow method writes `result.csv`, raw timing repetitions,
the sampled quality layout, and a complete two-dimensional `embedding.csv`.
A shared R renderer reads that CSV and writes `embedding.png`, so R and Python
methods use identical labels, palette construction, margins, opacity, and
point-size rules. Tasks also retain
`/usr/bin/time -v` output, CUDA memory traces, and the Slurm stdout/stderr log.
Comparator fits currently have a temporary 600-second per-method limit. Set
`METHOD_TIMEOUT_SECONDS` to a positive integer to override it. Input
precomputation is not subject to this limit. A timeout writes an explicit
`status.csv` row and cannot pass the final campaign audit.
The audit also checks that a successful method's reported family agrees with
its method name. The JSS figure builder requires `status=PASS` in
`final_audit.txt`; quality-diagnostic elapsed times cannot replace repeated
R CUDA public-call measurements.
Preflight also records package and image
identity, the loaded shared-object checksum, backend capabilities,
`sessionInfo()`, and `nvidia-smi` output.

The gallery builder requires one campaign result directory as its first
argument. It reads only that campaign's `embedding.csv` files and never scans
older PNG files by timestamp. This prevents mixed-release galleries.

```bash
Rscript analysis/build_table5_and_embedding_gallery.R \
  "$OUTPUT_ROOT"
```

The PCA, t-SNE, and UMAP timing table and gallery are generated from that same
campaign root. Failed or unavailable combinations remain explicit empty
positions rather than being replaced by results from another run.

Metal is not runnable on the Linux HPC. The same R driver can be used for a
separate local Apple Silicon campaign, but Metal evidence must not be inferred
from these CPU/CUDA jobs.
