# Resident one-case HPC worker

This candidate worker accepts one JSON case per invocation. The reviewed
`routes.json` currently enables only fastEmbedR CPU PCA, t-SNE, UMAP,
Leiden, and Louvain on the 11 comparison datasets. CUDA, comparators,
and Deep1B remain blocked until their resident routes and resource checks
are qualified.

CPU PCA, t-SNE, UMAP, Leiden, and Louvain landmark routes are staged for
the five declared comparison-data fractions. Embeddings fit selected rows
and project every input row in memory. Clustering fits a reference graph
and assigns query labels by distance-weighted vote, keeping reference
labels fixed. The worker checks landmark count, output row count, observed
backend, and fit/projection evidence. A 48-row PCA fixture, separate
120-row 3D t-SNE/UMAP fixtures, and 120-row Leiden/Louvain fixtures
completed against the isolated package candidate on Chiamaka. Deep1B
landmark cases remain blocked.
Landmark plans declare `expected_rows`; both planner and worker reject a
fraction whose count is too small for PCA rank, t-SNE perplexity/affinity
width, or the fixed 30-neighbor UMAP/clustering policy. The worker also rejects a
source whose observed row count differs from the plan before fitting.

The Python entry point validates the case, route, Slurm allocation,
single-fit count, and absence of GPU exposure in a CPU case. The R worker
loads an `.RData` matrix completely into process memory and calls the
package with `massive = "off"` for PCA, t-SNE, and UMAP. Clustering uses a
resident KNN graph and one coordinated CPU fit. It saves one final fit,
metrics, and provenance after the calculation. No scratch graph,
checkpoint, memory map, or streamed optimizer state is used.

The R worker now has a staged CUDA dispatch for one to three visible GPUs,
including coordinated device arguments for one fit. The entry point still
rejects CUDA, and `routes.json` has no eligible CUDA route. Its CUDA branch
requires device and lifecycle qualification before any HPC use. The R worker
independently rejects file-backed declarations and mismatched GPU visibility,
then checks the observed backend, device list, and result row count. It records
loading, fitting, and final writing as separate times. The configured CPU
worker count is distinct from a measurement of actual CPU utilization.
Resident t-SNE cases can declare perplexity, affinity width, and both
iteration counts. The output records the effective affinity policy, so
compact and conventional-support cases retain different identities.

The staged Deep1B path is stress-test only. On Silvano's Mac,
`prepare_deep1b_nested_10m.py` validates the existing 100M `% 10 == 0`
fbin and its manifest, then selects every tenth row of that file. This
produces exactly the one-based original-source `% 100 == 0` 10M subset.
It writes a separate 3,840,000,008-byte fbin and source-linked SHA-256
manifest under Stefano. The R loader verifies that manifest and the
subset checksum, then materializes a float32 matrix before fitting.
It does not expose a backed array or streamed optimizer state to the
scientific method. The Deep1B route is still blocked from HPC execution
until the prepared subset is transferred, resource limits and methods
are qualified, and `routes.json` is explicitly reviewed.

Run from a source-locked image with one case file in one Slurm allocation:

```text
/opt/conda/bin/python run_case.py CASE.json DATA_ROOT OUTPUT_ROOT
```

The entry point refuses to overwrite an existing case directory. It is
not a launcher and has not been deployed or submitted to the HPC. An atomic
claim file keyed by Slurm job and array task ID in the result root prevents a
second case from using the same allocation, including after a failed first
case. Separate array elements can run independent cases.

Local safety checks: `python3 -m unittest -v test_policy.py
test_deep1b_nested.py` covers policy and exact nested row selection.
The revised R worker completed CPU landmark PCA, conventional-width
t-SNE, UMAP, Leiden, and Louvain fixtures on Chiamaka;
file-backed and unallocated-CUDA cases stopped before fitting. Earlier
development runs covered the five CPU methods before this worker revision.
The resident Deep1B loader passed a small synthetic fixture in the
Chiamaka CPU container; no actual Deep1B data were copied there.
These checks do not establish benchmark quality or scaling.

Archived file-backed Deep1B, HNSW, and clustering launchers in this
candidate checkout exit with status 78 before submitting or calculating.
Historical result files remain untouched. The GPU campaign is still
paused under the separate HPC policy.
