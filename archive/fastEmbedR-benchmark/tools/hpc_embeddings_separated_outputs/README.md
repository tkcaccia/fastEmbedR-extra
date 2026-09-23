# fastEmbedR HPC benchmark bundle

This transfer bundle separates the ordinary embedding benchmark from the slow
KODAMA workflows and keeps numerical layouts outside the main result folders.

## Copy to the HPC

Copy all top-level files to `/scratch/firenze/NN` and the generated job
directory beside them:

```bash
cp benchmark_reviewer_validation.R publication_metrics.R \
  benchmark_worker_monitor.sh reference_opentsne_affinity.py \
  run_reviewer_dataset_job.sh submit_reviewer_dataset_jobs.sh \
  run_landmark_dataset_job.sh submit_landmark_dataset_jobs.sh \
  submit_kodama_dataset_jobs.sh /scratch/firenze/NN/

cp -R jobs_by_dataset /scratch/firenze/NN/
```

## Output layout

Each submitted job receives an independent run folder:

```text
/scratch/firenze/NN/fastEmbedR-results/
  <dataset>/<standard-or-kodama>/<cpu1-cpu4-cuda>/<timestamp_jobid>/

/scratch/firenze/NN/fastEmbedR-rlayout/
  <dataset>/<standard-or-kodama>/<cpu1-cpu4-cuda>/<timestamp_jobid>/
```

`fastEmbedR-results` contains CSV tables, logs, plots, timing records, memory
records, and reproducibility metadata. `fastEmbedR-rlayout` contains only the
saved R layout objects (`.rds`). Shared benchmark inputs and preprocessing
caches are stored under `fastEmbedR-input`, outside both result trees:

```text
/scratch/firenze/NN/fastEmbedR-input/
  precomputed/<dataset>/
  python_npz/<dataset>/
  reference_affinity/<dataset>/
  validation_knn/<dataset>/
  runtime_cache/
```

Standard, landmark, and KODAMA jobs reuse this common input tree across
replicates, thread counts, and backends.

All 99 dataset launchers are together under `jobs_by_dataset`. For example:

```text
run_MetRef_standard_cpu4.sh
run_MetRef_landmark_cpu4.sh
run_MetRef_kodama_cpu4.sh
```

## Submit ordinary benchmarks

```bash
cd /scratch/firenze/NN
bash submit_reviewer_dataset_jobs.sh
```

One backend profile can be selected explicitly:

```bash
PROFILE=cpu4 bash submit_reviewer_dataset_jobs.sh
PROFILE=cuda bash submit_reviewer_dataset_jobs.sh
```

These jobs exclude every KODAMA method.

## Submit landmark experiments

Landmark launchers are in the same `jobs_by_dataset` folder as every other
dataset launcher:

```bash
cd /scratch/firenze/NN
bash submit_landmark_dataset_jobs.sh
```

Each landmark job compares the full fastEmbedR embedding against a 50%
landmark embedding for openTSNE and binary UMAP. Select one profile with:

```bash
PROFILE=cpu4 bash submit_landmark_dataset_jobs.sh
PROFILE=cuda bash submit_landmark_dataset_jobs.sh
```

## Submit KODAMA only

```bash
cd /scratch/firenze/NN
bash submit_kodama_dataset_jobs.sh
```

Or submit one profile or one dataset:

```bash
PROFILE=cpu4 bash submit_kodama_dataset_jobs.sh
sbatch jobs_by_dataset/run_MetRef_kodama_cpu4.sh
```

For each seed, a KODAMA-only job fits the KNN core once and the PLS-LDA core
once. Each completed core is immediately visualized with openTSNE and UMAP, so
plots appear before the next slow core fit begins.

## Dry run

```bash
DRY_RUN=true PROFILE=cpu4 bash submit_reviewer_dataset_jobs.sh
DRY_RUN=true PROFILE=cpu4 bash submit_landmark_dataset_jobs.sh
DRY_RUN=true PROFILE=cpu4 bash submit_kodama_dataset_jobs.sh
```
