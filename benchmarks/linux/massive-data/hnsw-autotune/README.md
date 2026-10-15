# Deep/Turing HNSW calibration (CPU)

The completed 2026-10-08 screen and its focused follow-up plan are recorded
in [RESULTS_20261008.md](RESULTS_20261008.md).

The original exploratory campaign compared faissR 0.99.50's shape-based HNSW
settings with measured exact kNN recall, build time, sampled-query time,
and process peak RSS. It does not alter faissR or fastEmbedR defaults.

Inputs are the completed BigANN Deep1B and Turing1B `.fbin` files. The
launcher checks dimensions, size, and the download manifests without reading
all 784 GB again. The recorded source SHA-256 values are not reverified at
launch. A separate full hash check is necessary if storage integrity is in
doubt.

Each dataset has a 20,000-row pilot and a 1,000,000-row prefix validation.
The latter is still a prefix of the billion-row dataset, not a 1B-index test.
We test k=15,30,50; 20k-row shards (plus 50k-row shards and an unsharded
1M-row reference at 1M rows);
M/efConstruction in the generated case table; and efSearch 45,60,80,120,150,
240,480,960 where efSearch is at least k+1. Each index is built once per
build configuration and reused for
all requested `k` and efSearch values. A separate `k+1` search is made for
each k so self-removal matches the actual workload. There is no NN-descent or
algorithm substitution. The grid includes the current faissR preset for
each tested `k` and shard size, allowing a direct baseline comparison.

The truth jobs compute exact Euclidean neighbors for 2,048 seeded random
query rows per scope. Scale queries begin after the pilot's first 20,000
rows, so pilot-to-scale transfer uses unseen query points. Disjoint samples
of 1,024 rows form tuning and holdout sets.
This gives 1,024 tuning and 1,024 holdout queries, meeting FAISS's lower
query-count guidance. It remains a screening sweep over two dataset prefixes,
not enough by itself to set a new default. A setting is a candidate only
when a normal-approximation 95% lower bound on mean tuning recall reaches
0.99; holdout and pilot-to-scale transfer are reported separately. Inspect
row-level failures before making a default policy. Among recall-qualified
settings, the screen nominates the lowest projected build-plus-query time
for the declared all-row workload (20,000 or 1,000,000 queries). The
independent holdout recall is reported, never used to pick the setting.
The projection uses median repeated search time per query, adds measured
collection and merge time per query, then adds index-build time. It excludes
calibration cost and is not a measured full-workflow runtime.
Pilot timings use 25
repeated full-query passes; scale timings add three 128-query passes for
noise assessment. Timings include full
sample search and cross-shard merge, but not an all-rows production fit;
memory is a case-level process high-water mark, not per-efSearch memory.
Index build tasks may land on different nodes, so the rank ordering of
close timings is not conclusive.
Deep and Turing informed this candidate grid. Their holdout queries test
within-data-set selection, not independent generalization of the grid;
a frozen policy must also be evaluated on previously unused data sets.

No input copies, embeddings, full indexes, or large result matrices are
saved. `truth/*.rds` holds only query IDs and exact top-51 results.
The small `truth/*_geometry.csv` files describe exact-neighbor distance
ratios. `truth/*_timing.csv` records exact-reference and truth-worker time.
`sweep/*_queries.csv` retains per-query k=30 recall to inspect hard cases;
no source vectors are stored.

## Install and launch

From the Mac, sync the whole directory (not an individual file):

```bash
SRC=/Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/massive-data/hnsw-autotune
HOST=01481067@hex.uct.ac.za
REMOTE=/scratch/firenze/NN/benchmark_scripts/massive-data/hnsw-autotune
ssh "$HOST" "mkdir -p '$REMOTE'"
rsync -av --exclude='__pycache__/' "$SRC/" "$HOST:$REMOTE/"
```

Then, from the HPC login node (submission only; no Singularity there):

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/massive-data/hnsw-autotune/submit.sh
```

The command automatically schedules 4 exact-truth jobs, 52 HNSW sweep
jobs, a pilot report, and 1 final audit on `ada`. No L40S allocation is
required. Sweeps
wait only for truth from the same scope: pilot results can arrive while 1M
truth is still running. The audit runs even if some tasks fail. Copy the printed
campaign path.

### Fresh 5M-row screen after the new image

Once the faissR 0.99.52 / fastEmbedR candidate image has passed its own
preflight and replaced the stable HPC image, sync this whole suite again and
submit the bounded independent-prefix screen:

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/massive-data/hnsw-autotune/submit_5m.sh
```

This submits a compute-node package/ABI preflight, separate exact-reference
jobs for Deep and Turing, three prespecified HNSW search cases, and an audit.
The input is a file-backed view of rows 1,000,001--6,000,000 in each BigANN
file. No vector copy or full KNN graph is produced. Each dataset's sweep
waits only for its own exact truth. The audit runs after both sweeps, even
if a job fails. `audit_5m.json` distinguishes missing tasks from candidates
whose untouched-holdout bootstrap lower bound misses 0.99;
`screen_5m.csv` reports recall, build/search time, and worker peak RSS.
The 5M screen is a gate for later paired same-node and full-graph tests, not
a production speed comparison. Its exact experimental order and promotion
rules are in [RESULTS_20261008.md](RESULTS_20261008.md).

### Independent 5M-row effort refinement

With faissR 0.99.52 or newer in the source-locked image, run:

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/massive-data/hnsw-autotune/submit_5m.sh refine
```

This reads rows 6,000,001--11,000,000, a new window beyond both the 1M
development prefix and the first 5M screen. Three HNSW build cases each
reuse one index over `efSearch` 45, 60, 80, 120, 150, and 240. The
8,192 exact-reference queries are split into tuning and untouched holdout
halves. `refine_5m.csv` reports both a bootstrap lower bound on mean recall
and the fraction of queries missing at least one top-30 neighbor. The
predeclared consistency gate allows at most 1% such queries; it is more
conservative than mean recall alone. `audit_refine.json` reports structural
completeness and the number of holdout efforts passing both gates. This
screen does not build a full graph or promote a package default.

Do not run `submit_5m.sh` against an earlier faissR image. Each worker
verifies the source-locked image SHA-256; the preflight tests the explicit
persistent FAISS HNSW bridge before the data jobs proceed.

For either campaign, monitor with:

```bash
squeue -u "$USER" -o '%.18i %.24j %.2t %.10M %R'
ROOT=/scratch/firenze/NN/fastEmbedR-results/massive-data/hnsw-autotune
RUN=$(find "$ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)
printf 'Campaign: %s\n' "$RUN"
cat "$RUN/jobs.tsv"
for file in pilot_status.json audit.json audit_5m.json \
    audit_refine.json failures.tsv; do
    if [ -f "$RUN/$file" ]; then cat "$RUN/$file"; fi
done
```

To copy only evidence back to the Mac after completion, use `rsync -av` on
the printed campaign directory; it contains no copied input matrices.

## Interpretation

- `sweep_summary.csv`: all build/search settings and measured recall for
  both tuning and holdout queries; faissR's policy is recorded in each row.
- `pilot_screen.csv` and `pilot_passing.csv`: available once the pilot lane
  finishes, even if scale jobs are still running. The screen nominates the
  lowest projected full-workload time among recall-qualified settings.
  Cross-node differences are provisional, and `holdout_confirmed` must be
  checked separately. Inspect
  `pilot_status.json` first.
- `recommendations.csv`: the lowest projected build-plus-all-row-query
  time among settings with a normal-approximation 95% lower bound above
  0.99 on tuning queries, plus its untouched holdout mean. This is a
  provisional speed candidate, not a measured production winner or a new
  default. `holdout_confirmed` records an independent recall check.
  Confirm finalists with repeated same-node end-to-end fits.
- `faissr_baselines.csv`: faissR's present settings, their observed holdout
  recall when swept, or an explicit `outside_search_grid` marker.
- `pilot_transfer.csv`: whether the pilot's choice also reaches 0.99 in
  the 1M-row, 20k-shard validation.
- `pareto_points.csv`: exploratory non-dominated observed holdout recall,
  sampled query time, build time, and case-level RSS; cross-node timing
  differences need same-node confirmation.
- `amortized_estimates.csv`: all recall-eligible candidates with projected
  build-plus-query seconds for three explicit query counts. These are linear
  extrapolations from one sampled pass, not measured full-call timings or
  a ranking to use for defaults.
- `experiment_cost.csv`: exact-reference and exhaustive-sweep worker-time
  sums. These include repeated diagnostic measurements and are not the cost
  of a future bounded fine tuner; parallel worker-time sums are not campaign
  wall time. A data-aware workflow speed comparison must time its actual
  calibration and final fit together.
- `failures.tsv` and `audit.json`: task completeness, separate from recall
  misses. `unconfirmed_speed_candidates` counts nominated settings that
  miss the independent holdout bound. Low recall is an experimental result,
  not a task failure.

The original 20k/1M sweep uses faissR's internal Rcpp HNSW wrappers to
study the algorithm
and tuning policy. It does not validate fastEmbedR's complete KNN, UMAP, or
t-SNE call, nor its current file-backed HNSW bridge, whose shape policy may
differ from faissR 0.99.50. The new 5M screens use the shared explicit
bridge and record faissR 0.99.52 identity. No full-workflow speed ratio
follows from this
sweep. A separate bridge test is required after both packages share one
native policy. The sweep does not validate the versioned public C ABI. Queries
are sampled from the indexed dataset rather than an external query set;
the 1M unsharded cases help distinguish general HNSW behavior from
fastEmbedR's sharded route. Full 1B-index behavior is not measured.

FAISS guidance: [Index IO, cloning and hyper parameter tuning](https://github.com/facebookresearch/faiss/wiki/Index-IO,-cloning-and-hyper-parameter-tuning).
