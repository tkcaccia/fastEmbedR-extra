# Classifier-specific KODAMA benchmark

This benchmark evaluates `classifier = "pls_lda"` and `classifier = "knn"`.
Each KODAMA fit is computed once and reused for both
`KODAMA.visualization(..., "openTSNE")` and
`KODAMA.visualization(..., "UMAP")`.

The neighborhood graph is also computed exactly once for each
dataset/backend pair with `KODAMA.graph()`. The serialized checkpoint is saved
under:

```text
fastEmbedR-input/kodama_graphs/<dataset>/<cpu4|cuda>/kodama_graph_k100_seed4.rds
```

Every PLS-LDA/KNN and landmark analysis reloads that same checkpoint. The
worker calls `KODAMA.matrix(data = raw_features, graph = prepared_graph, ...)`
under the current API. It verifies the dataset path, file size, modification
time, dimensions, graph parameters, and backend before fitting. It also
requires `KODAMA.matrix()` to report `graph_builds = 0`. Missing or
incompatible checkpoints are hard failures; the benchmark never silently
recomputes a graph.

The worker also checks that the installed `KODAMA.matrix()` exposes the
`graph` formal argument. An image containing the former
`KODAMA.matrix(data = graph, raw.data = raw_features, ...)` wrapper is rejected
before analysis starts.

For every dataset, the generated jobs run the established large landmark
request (`landmarks = 10000000`). KODAMA applies its documented 75% rule when
that request is at least the number of samples. Datasets with more than 10,000
samples additionally receive exact 10%, 20%, and 50% landmark requests. Each
landmark setting has its own Slurm allocation so a slow setting cannot prevent
the other settings from starting.

Every analysis launcher is a three-task Slurm array. Seeds 4, 17, and 42 therefore
receive independent 48-hour allocations rather than sharing one allocation.
The collector recombines the tasks into median/IQR summaries. Outputs include:

- graph checkpoint path, graph-precomputation time, and graph-reuse audit;
- KODAMA core, visualization, and complete-workflow runtime;
- peak process RAM and device-wide peak GPU-memory delta;
- selected CV accuracy, number of clusters, ARI, and NMI;
- trustworthiness, KNN preservation, silhouette, and label KNN accuracy;
- compact model summaries, layouts, and clean truth/KODAMA-label plots;
- median and IQR summaries over the three seeds.

Generate the CPU-4 and CUDA launchers on the HPC:

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/generate_seed_grouped_kodama_jobs.sh
```

Submit CPU-4 and CUDA independently:

```bash
cd /scratch/firenze/NN
bash kodama_classifier_jobs_by_dataset/seed_grouped/submit_cpu4.sh
bash kodama_classifier_jobs_by_dataset/seed_grouped/submit_cuda.sh
```

Each submitter first schedules the dataset/backend graph job, captures its
Slurm job ID, and submits the corresponding analysis array with an
`afterok:<graph-job-id>` dependency. To submit one dataset manually:

```bash
graph_id="$(sbatch --parsable \
  kodama_classifier_jobs_by_dataset/graph_precompute/prepare_kodama_graph_MetRef_cpu4.sh)"
graph_id="${graph_id%%;*}"
sbatch --dependency="afterok:${graph_id}" \
  kodama_classifier_jobs_by_dataset/seed_grouped/run_kodama_seed_grouped_MetRef_cpu4.sh
```

Collect completed summaries:

```bash
apptainer exec \
  --bind /scratch/firenze/NN:/scratch/firenze/NN \
  singularity/fastembedr_cuda.sif \
  /opt/conda/bin/Rscript \
  benchmark_scripts/kodama_classifier_benchmark/collect_kodama_classifier_results.R \
  /scratch/firenze/NN/fastEmbedR-results
```
