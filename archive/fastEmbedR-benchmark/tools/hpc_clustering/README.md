# Clustering backend validation

This benchmark separates two computational boundaries:

1. `knn_graph()` constructs the weighted graph with CPU or CUDA nearest-neighbor
   search.
2. `graph_cluster()` runs fastEmbedR's native CPU, CUDA, or Metal Louvain and
   Leiden implementation. Pons-Latapy Walktrap is explicitly CPU-only.

CUDA and Metal clustering do not link to RAPIDS cuGraph. CUDA jobs run the
package's own kernels; optional cuGraph rows can still be enabled as external
oracles. cuGraph does not provide Pons-Latapy Walktrap.

Every native result is compared with the corresponding `igraph` method on the
identical weighted graph. The output reports runtime, modularity, label ARI/NMI,
partition ARI/NMI versus `igraph`, community counts, requested and used
backends, CPU threads, and seed. Datasets larger than 100,000 observations use a
fixed stratified validation subset; the original and tested sizes are both
recorded. Walktrap is skipped above 4,000 vertices because the package's exact
implementation has quadratic state.

Install the files under `/scratch/firenze/NN/benchmark_scripts/hpc_clustering`
and submit the three independent benchmarks:

```bash
cd /scratch/firenze/NN
sbatch benchmark_scripts/hpc_clustering/run_clustering_validation_cpu1.sh
sbatch benchmark_scripts/hpc_clustering/run_clustering_validation_cpu4.sh
sbatch benchmark_scripts/hpc_clustering/run_clustering_validation_cuda.sh
```

After all three jobs finish, aggregate the newest profile from each backend:

```bash
sbatch benchmark_scripts/hpc_clustering/run_clustering_validation_aggregate.sh
```

Results are written below:

```text
/scratch/firenze/NN/fastEmbedR-results/clustering_validation/
```

The aggregate job writes:

- a complete seed-level CSV;
- median and IQR summaries;
- CPU1/CPU4/CUDA graph-construction speedups;
- native-versus-igraph ARI, NMI, and modularity agreement;
- publication-ready graph-runtime and agreement figures.

For a self-contained synthetic accelerator test that excludes KNN time and
warms one-time device initialization, run:

```bash
Rscript benchmark_native_accelerators.R \
  --n=50000 \
  --backends=cpu,cuda \
  --seeds=4,17,42 \
  --out-dir=native_clustering_cuda
```

To validate a saved real graph without repeating nearest-neighbor search or
graph construction, use:

```bash
Rscript benchmark_cached_graph.R \
  --graph=mnist70k_snn_graph_k30.rds \
  --labels=mnist70k_labels.rds \
  --backends=cpu,cuda \
  --seeds=4,17,42 \
  --out-dir=mnist70k_clustering_cuda
```

The cached-graph benchmark records median and IQR runtime, modularity, label
adjusted Rand index, partition agreement with `igraph`, community count, and
the Leiden connected-community invariant.
