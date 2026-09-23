# Handoff: prepare the KODAMA CPU4 ablation benchmark on the HPC mirror

## Objective

Modify and place the R and Slurm files in the local HPC-synchronized directory
`/Users/stefano/HPC-firenze/NN`. On the cluster this directory is
`/scratch/firenze/NN`.

Implement the experiment specified by:

`/Users/stefano/Documents/KODAMA-cpp 2/docs/JMLR_CPU4_ABLATION_HPC_PROTOCOL.md`

Prepare and validate the scripts, but **do not call `sbatch` and do not launch
jobs**. The user will inspect and submit them.

## Non-negotiable constraints

1. This experiment is CPU-only. Do not use CUDA or Metal.
2. Each process must receive exactly four CPU workers. Use one Slurm task and
   four CPUs per task:

   ```bash
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=4
   ```

3. Configure native OpenMP for four workers and prevent nested BLAS threading:

   ```bash
   export OMP_NUM_THREADS=4
   export RCPP_PARALLEL_NUM_THREADS=4
   export OPENBLAS_NUM_THREADS=1
   export MKL_NUM_THREADS=1
   export VECLIB_MAXIMUM_THREADS=1
   export NUMEXPR_NUM_THREADS=1
   ```

4. Use `M = 100`, `Tcycle = 100`, seeds `4, 17, 42`, five CV folds,
   `landmarks = 100000`, graph `k = 100`, and the protocol's splitting rule.
5. Truth labels must never be passed to KODAMA, graph construction, PCA,
   initialization, policy selection, or run selection. Use them only after a
   fit has completed to calculate diagnostics.
6. Never silently fall back to a different backend, policy, predictor setting,
   dataset representation, or smaller dataset.
7. Do not emulate missing KODAMA policies in R. The policy must be implemented
   inside `kodama-cpp` and exposed by `kodamaR`.
8. Preserve explicit failed and timed-out rows. Do not omit unsuccessful cells.
9. Write every result atomically to a unique cell directory.
10. Do not edit or delete existing benchmark results.

## Required KODAMA API preflight

Before generating full jobs, inspect:

```r
names(formals(kodamaR::KODAMA.matrix))
```

The installed wrapper must expose:

```text
data
graph
M
Tcycle
folds
ncomp
landmarks
splitting
n.cores
graph.neighbors
knn.k
classifier
backend
seed
evolution.policy   # evolution_policy is acceptable if that is the frozen API
```

The named policies must be:

```text
full
no_prediction_guidance
fixed_proposal_budget
no_transition_proposal
greedy_acceptance
raw_cv_score
no_pls_transition_coarsening
no_pls_fragmentation_penalty
```

If the API or any named policy is absent, create a machine-readable preflight
failure and stop. Do not generate fake ablation results from ordinary `full`
runs.

Also verify that the returned fit exposes the internal diagnostics required by
the protocol: per-cycle proposal sizes, accept/reject decisions, improving and
temperature acceptance, proposal-type counters, active-class counts, CV
evaluation counts, run-level accuracy and score vectors, landmark rows,
initial labels, fold assignments, and agreement-prefix diagnostics. If these
are absent, stop before the full array.

## Freeze the release

Create a release manifest containing:

- full `kodama-cpp` commit SHA;
- full embedded `kodamaR` wrapper SHA;
- package version;
- Singularity/Apptainer image path, size, and SHA-256;
- `kodamaR` shared-library SHA-256;
- compiler, CMake, build type, OpenMP runtime, and build flags;
- R and package versions;
- operating system, CPU model, physical/logical CPU count, and memory;
- all thread-related environment variables;
- complete command line and timing-boundary definition.

Reject mixed core or wrapper SHAs during aggregation.

## Dataset registry

Use these complete datasets under `/scratch/firenze/NN/Data`:

```text
COIL20/COIL20.RData
FashionMNIST/FashionMNIST.RData
MNIST/MNIST.RData
Macosko2015_retina/Macosko2015_retina.RData
MetRef/MetRef.RData
TabulaMuris/TabulaMuris.RData
USPS/USPS.RData
flow18/flow18.RData
imagenet/imagenet.RData
mass41/mass41.RData
FlowRepository_FR-FCM-ZYRM_files/van_unen_FR-FCM-ZYRM.RData
```

Each RData file should provide a list with `$data` and `$labels`. Support the
existing `$label` alias only when necessary. Validate dimensions, finite
values, and label length. Create a dataset manifest with data and label
checksums, sample count, variable count, class count, dtype, source,
preprocessing, version, and license.

ImageNet has two registered representations:

- `imagenet_raw`: supplied raw DINOv2 features;
- `imagenet_pca50`: one CPU4 `KODAMA.pca()` calculation from the raw matrix.

Compute ImageNet PCA50 once, without labels. Save its scores, options, runtime,
singular values or explained variance, sample-order checksum, and matrix
checksum. Reuse this file in all cells; do not recompute PCA per seed or policy.

## Graph preparation

For each `dataset x representation x seed`, run exactly once:

```r
graph <- kodamaR::KODAMA.graph(
  data = x,
  k = 100L,
  metric = "euclidean",
  backend = "cpu",
  n.cores = 4L,
  seed = seed,
  storage = "matrix"
)
```

Use `storage = "matrix"` because process-local external-pointer handles cannot
be serialized across Slurm jobs. Save the materialized graph, PCA starts,
sample-order checksum, graph checksum, graph construction time, graph bytes,
and metadata. Every classifier, ablation, and sensitivity cell for that key
must load the same graph file. Record its SHA-256 in every cell manifest.

## Experiment cells

Create one scheduler cell per:

```text
dataset x representation x classifier x experiment x setting x seed
```

### Experiment A: isolated ablations

KNN and PLS-LDA:

```text
full
no_prediction_guidance
fixed_proposal_budget
no_transition_proposal
greedy_acceptance
raw_cv_score
```

PLS-LDA only:

```text
no_pls_transition_coarsening
no_pls_fragmentation_penalty
```

Use `knn.k = 30` and requested `ncomp = 50`. Every variant must retain the
same graph, landmark rows, initial labels, folds, number of CV evaluations,
projection, correction, and visualization settings. Verify the matched hashes.

### Experiment B: predictor sensitivity

Use only `evolution.policy = "full"`:

```text
KNN:     k = 10, 30, 50, 100
PLS-LDA: ncomp = 5, 10, 20, 50
```

The graph always remains at 100 neighbors. Record requested and evaluated
values. Mark mathematically identical capped component cells as duplicates;
do not present them as independent runs.

### Experiment C: ImageNet raw versus PCA50

Run the full ablation and sensitivity panels on both representations. Also run
classic fuzzy UMAP (`k = 30`) and classic openTSNE (`perplexity = 30`) from the
same representation. Report downstream time and complete PCA-inclusive time.

## Smoke phase and dependencies

Create a smoke array first with `M = 2`, `Tcycle = 2` for every dataset,
representation, classifier, and policy. Smoke outputs must be stored separately
and excluded from manuscript aggregation.

Generate Slurm scripts with this dependency order:

```text
preflight
  -> ImageNet PCA50 preparation
  -> graph preparation array
  -> smoke cell array
  -> smoke schema validation
  -> full cell array
  -> aggregation afterany
```

Use `afterok` through full-cell submission so invalid preparation cannot launch
expensive work. Use `afterany` only for aggregation so failures are retained.

Write a `submit_all.sh` that performs these submissions and captures job IDs,
but do not execute it.

## R driver behavior

The full fit should follow this pattern:

```r
fit <- kodamaR::KODAMA.matrix(
  data = x,
  graph = prepared_graph,
  M = 100L,
  Tcycle = 100L,
  folds = 5L,
  ncomp = requested_ncomp,
  landmarks = 100000L,
  splitting = if (nrow(x) < 40000L) 100L else 300L,
  n.cores = 4L,
  graph.neighbors = 100L,
  knn.k = requested_k,
  classifier = classifier,
  backend = "cpu",
  seed = seed,
  evolution.policy = policy,
  visual.init = TRUE,
  progress = TRUE
)
```

Use the frozen wrapper's exact spelling if it exposes `evolution_policy`.

Generate both visualizations from the same fit:

```r
umap <- kodamaR::KODAMA.visualization(
  fit, method = "UMAP", k = 30L, graph.mode = "fuzzy",
  backend = "cpu", n.cores = 4L, seed = seed
)

tsne <- kodamaR::KODAMA.visualization(
  fit, method = "openTSNE", perplexity = 30,
  backend = "cpu", n.cores = 4L, seed = seed
)
```

Do not choose an ablation from plots or external labels. Determine the
strongest adverse ablation only from the predefined internal primary metric.

## Required output structure

Write to a new immutable run directory:

```text
/scratch/firenze/NN/kodama_cpu4_ablation_<release>/
  release_manifest.json
  dataset_manifest.csv
  cells.csv
  graphs.csv
  smoke/
  prepared_graphs/<dataset>/<representation>/<seed>/
  cells/<dataset>/<representation>/<classifier>/<experiment>/<setting>/<seed>/
    manifest.json
    metrics.csv
    run_metrics.csv
    cycle_deciles.csv
    timing.csv
    memory.csv
    labels.rds
    graph_metadata.json
    umap.csv
    opentsne.csv
    stdout.log
    stderr.log
    exit_status.txt
  aggregate/
    all_cells.csv
    all_runs.csv
    ablation_dataset_effects.csv
    predictor_sensitivity.csv
    imagenet_raw_pca50.csv
    failures.csv
    figures/
  checksums.sha256
```

Never overwrite a prior successful cell. A rerun should skip a valid success
or write to a new attempt directory.

## Metrics and statistical analysis

Implement every metric listed in the protocol, including internal CV and
acceptance diagnostics, collapse and solution-diversity measures, agreement
convergence at M prefixes 10/20/50, external clustering diagnostics,
trustworthiness and neighborhood preservation at 15/30, pair-distance rank
correlation, graph integrity, complete stage timings, worker utilization, peak
RSS, graph/object bytes, warnings, fallbacks, and non-finite counts.

The aggregator must:

1. reject duplicate complete cell keys;
2. reject mixed commits, images, dataset checksums, or graph checksums;
3. verify `CV evaluations = M * (Tcycle + 1)` unless a mathematical degeneracy
   is explicitly recorded;
4. calculate full-minus-ablation differences within dataset and seed;
5. reduce seeds by dataset median;
6. calculate dataset-bootstrap 95% intervals, exact paired Wilcoxon tests, sign
   tests, matched rank-biserial effects, Holm correction, and leave-one-dataset-
   out summaries;
7. keep ImageNet raw/PCA50 and predictor-sensitivity analyses descriptive and
   never select settings from truth-label metrics.

## Deliverables to report before submission

Return to the user:

- exact files created or modified under `/Users/stefano/HPC-firenze/NN`;
- frozen core/wrapper/image identities;
- preflight findings;
- number of graph, smoke, and full cells;
- expected Slurm dependency chain;
- copy-paste command that generates scripts;
- copy-paste command that the user may later use to submit them;
- explicit confirmation that no job was submitted.

