# Experimental file-backed scaling checks

For the official billion-vector Turing-ANNS and DEEP sources, required
storage, terms, and resumable HPC commands, see
[BIGANN_DATASETS.md](BIGANN_DATASETS.md).

## CUDA reference-shard comparison

Generate the input in a separate bounded process before measuring KNN.
The earlier one-process diagnostic's peak RSS included allocation of a
full R double matrix; see the [corrected evidence][shard-evidence].

```bash
python3 generate_input.py --rows 1000000 --columns 32 \
  --distribution gaussian --chunk-rows 10000 \
  --output /path/to/run/input.f32
Rscript compare_cuda_sharded_knn.R PRIVATE_LIBRARY SOURCE_ARCHIVE \
  /path/to/run/exact-four exact /path/to/run/input.f32 250000 8192
```

The driver requires the generator's manifest and checks its dimensions,
file size, and SHA256. Use a fresh R process for each route and
`/usr/bin/time -v` for process-wall timing. The result CSV records
Linux process peak RSS separately from package working-buffer estimates.
`measure_cuda_script.sh` can sample GPU memory; set
`FASTEMBEDR_EXTRA_BIND=HOST_DIR:CONTAINER_DIR` when the input and private
library are outside its standard bind. GPU samples are observations,
not guaranteed instantaneous peaks.

[shard-evidence]: evidence/cuda-streamed-input-shard-20261004/README.md

This is a functional stress test for the **experimental** massive-data API,
not a publication-quality embedding-quality benchmark. It keeps synthetic
input generation, PCA, landmark UMAP, landmark t-SNE, and landmark clustering
execution in bounded chunks. No
large generated matrices or graph files belong in Git; small audit CSVs are
retained under `evidence/`. The runner checks the loaded package
version and CUDA metadata; it never treats a CPU fallback as a GPU success.

For a matched one-versus-two-GPU full-KNN recall and resource check, run
the current fastEmbedR source on a two-GPU Linux machine with an ANN
`.fbin` input:

```bash
python3 measure_multigpu_knn_matched.py \
  validate_multigpu_knn_matched.R /path/to/base.fbin \
  100000 30 /path/to/new-audit-directory 64
```

The wrapper rejects an existing output directory and writes
`resource_peak.csv`, `fit.out`, and `fit.err`. Its `run/` subdirectory
contains `matched_rows.csv`, `ivf_settings.csv`, `summary.csv`,
`gpu_device_map.csv`, and `provenance.rds`. Both fits are audited on the
same nonpilot query rows against one streamed exact reference. The
resource CSV has separate `one_gpu`, `two_gpu`, `audit`, and `overall`
phase rows. It samples process-tree RSS, process-attributed VRAM by GPU
UUID, and apparent/allocated generated payload bytes every 250 ms.
These are observed samples, not theoretical or guaranteed instantaneous
peaks. The two-GPU phase retains the first fit's graph until the audit
finishes, so its disk peak represents cumulative campaign storage. The
source input is excluded from generated payload bytes.
If GPU process attribution or either expected device is missing, the
GPU status is `unavailable` and the wrapper fails rather than reporting
zero use. It also fails if any audited row misses 0.99 ID recall. Graph
payloads created for a successful audit are removed unless
`MATCHED_KNN_KEEP_GRAPHS=1` is set.

After the massive-data backend is complete, add a separate scientific-usefulness
benchmark for Walktrap against Louvain and Leiden on the same real-data graphs.
Measure clustering agreement with available labels, seed and graph-parameter
stability, cluster-size behavior, runtime, and peak memory. Keep this study
separate from synthetic graph throughput checks; it is not a release gate for
the massive-data backend.

Focused two-A10G PCA and landmark-projection results are recorded in
`HF_MULTIGPU_PCA_20261001.md`; they are functional tests, not scaling claims.

The posting-index recall and amortization diagnostic is recorded in
`evidence/POSTING_HNSW_AMORTIZATION_20261001.md`. It does not support
replacing the current exact scan within selected postings with native HNSW.
The [full-row MNIST70k check](evidence/mnist70k-pca30-postings-20261002/README.md)
compares eight and 16 physical posting probes with exact CPU neighbors
on the same file-backed PCA scores. Its 64-row sampled audit missed the
worst full-graph recall failures, so mean sampled recall cannot by itself
authorize an automatic routing policy.
The [center-training and posting-list sweep][routing-sweep] shows that
larger training samples and finer lists still leave a low-recall tail.
An [oracle-distance posting-radius diagnostic][radius-bound] found that
a simple exactness bound would still scan most MNIST70k rows. This
rules out that bound as a useful default for the current postings.
The [MNIST70k full fuzzy UMAP integration][mnist-full-umap] reuses one
exact file-backed KNN and compares a matched file-backed layout with
the resident CPU optimizer on all rows.

[routing-sweep]: evidence/mnist70k-center-training-20261002/README.md
[radius-bound]: evidence/posting-radius-bound-mnist70k-20261002/README.md
[mnist-full-umap]: evidence/mnist70k-full-umap-20261002/README.md

Run in a private directory on a machine with the required package installed:

```bash
mkdir -p /path/to/private-run
python3 generate_input.py --rows 1000000 --columns 96 \
  --output /path/to/private-run/input.f32
Rscript run_scaling.R --input /path/to/private-run/input.f32 \
  --rows 1000000 --columns 96 --mode pca --backend cpu \
  --library /path/to/private-R-library --expected-version 0.1 \
  --expected-dll-sha256 YOUR_VALIDATED_DLL_HASH \
  --n-cores 4 --components 30 \
  --chunk-rows 10000 --memory-limit 256MB \
  --output /path/to/private-run/pca_cpu.f32 \
  --csv /path/to/private-run/pca_cpu.csv
```

Use `--backend cuda --n-cores 1` only on a GPU machine. For landmark UMAP,
use `--mode umap --landmarks 100 --neighbors 10` and a new output path.
For landmark t-SNE, use `--mode tsne --landmarks 100 --perplexity 15` and
optionally `--transform-iter 10`. The short default transform is only a
file-backed execution check, not a quality setting. For landmark clustering,
use `--mode cluster --cluster-method leiden --landmarks 100 --neighbors 10`.
To reuse an earlier landmark UMAP or t-SNE query graph, add
`--reuse-nn-model /path/to/earlier.model.rds` and set the same `--landmarks`,
`--transform-k`, backend, and input source. The package validates source,
landmark, graph, and backend identities; the runner fails if reuse is not
reported and records `graph_reused` in its CSV. The previous model and graph
files must remain at their original paths.
For a five-repetition CPU check of clustering reuse, see
[`benchmark_cluster_reuse.R`](benchmark_cluster_reuse.R) and the
[final-archive evidence](evidence/cluster-knn-reuse-final-20261002/README.md).
The same checked archive also passed a
[one-million-row CPU reuse diagnostic](evidence/cluster-knn-reuse-1m-cpu-20261002/README.md).
A further [bounded-output verification](evidence/cluster-knn-reuse-bounded-1m-20261002/README.md)
checked every saved assignment without a full-result R vector.
Clustering writes `<output>.clusters.u32` and
`<output>.confidence.f32`; other modes write float32 coordinates at
`<output>`. Each mode also writes a small model RDS and a status CSV.
Inside Singularity, bind the directory containing the private R library and
input file, and add `--nv` only for CUDA runs. The runner selects that library
with `--library`, rather than relying on the container's R library environment.
For CPU PCA with more than 1,024 columns, the runner selects the experimental
streamed randomized sketch. Its CSV records `pca_method` and
`pca_sketch_size`. Wide CUDA PCA uses CPU streamed moments and a CUDA
sketch and projection; the CSV records those stages separately. The `--seed`
option (default `4`) is passed to every mode and saved in the CSV.
Inputs are deterministic but synthetic; a successful layout is not evidence
of scientific quality. The generated `.sha256` file identifies the input.
For an input larger than available RAM or VRAM, `--repeat-chunk` writes a
real file by repeating one deterministic block. This is an I/O and memory
stress case with only `chunk-rows` unique observations; do not use its
embedding as a quality result.
The result CSV records wall time, the Linux process peak RSS, and the
package's algorithm-buffer and VRAM estimates. These estimates are **not**
process-memory ceilings: R and CUDA runtime allocations also consume memory.
It also records fitted rows per second, CPU seconds and equivalent cores,
and Linux process I/O counters. `process_read_bytes` and
`process_write_bytes` count storage I/O attributed to the process; cached
reads may not increase them. `logical_read_bytes` and
`logical_write_bytes` count requested I/O, not physical disk traffic.
The corresponding MiB-per-second fields divide process I/O by fit time.
These counters are `NA` outside Linux and do not measure GPU transfers.
`rss_delta_bytes` is the increase in Linux `VmHWM` after package loading and
source setup, not the absolute memory required to start the process. The
runner samples first, middle, and last rows for finite coordinates or
valid cluster labels and confidences; it does not inspect every row or
measure quality. It
does not validate that a dataset exceeds physical RAM or VRAM. A companion
`.model.rds` retains the small fitted model and file descriptors, not the
complete scores, embedding, or cluster assignment vector.

A 2026-09-30 wide-CUDA PCA smoke run used a 100,000 x 1,200 float32 file
(480 MB; SHA-256 `a856d023bb264eed6b5247b48bf0cc0c75cec6086355bf18359371cace6aa8ec`)
with 30 components and 500-row chunks. Source archive SHA-256 was
`5f29a4c3fc6b815c4b4a2d1e5a7eeaa3b1869061058d6841a27946ddc39667b3`;
the Chiamaka image SHA-256 was
`54e9604d951ecb3d80f49671d9db7a35cf19f1342eb3ee7c708cbc0c3a7f0aa8`.
The runner reported CPU moments, CUDA sketch and projection, 0.969 seconds
for the PCA call, a 12 MB output, and a process peak RSS of 641 MB. Its
74 MB algorithm-RAM estimate excludes R and CUDA runtime overhead. This
single synthetic run verifies the route and reporting, not beyond-RAM
operation, embedding quality, or a comparative speedup.

A separate 2026-09-30 CUDA PCA stress run used 50,000,000 x 96 float32
rows (19.2 GB on disk), exceeding the 16 GiB RAM then available and
the RTX 5060 Ti's 15,229 MiB free VRAM. The generator repeated a 10,000-row
block, so this is an I/O and memory test, not a quality dataset. With
10,000-row batches, four CPU workers, two components, and a 256 MB
algorithm-buffer limit, the PCA call took 117.149 seconds and wrote
400,000,000 score bytes. Linux `VmHWM` reached 632,725,504 bytes,
including the R/CUDA runtime; sampled GPU usage peaked at 933 MiB,
319 MiB above the pre-run baseline. These are observed usage figures,
not the package's smaller buffer estimates. A full sequential scan of
input and scores passed against dense PCA on the repeated block; the
maximum score discrepancy was 7.51e-7. The run used dirty source at
`525fc2901fecb85ae6b331f2c21761b3c1aa5f16`, source archive SHA-256
`799a48372ddfaebd5700bc0af2d55e13ad157968aa1057a0802818c47cc63b2a`,
and image SHA-256
`54e9604d951ecb3d80f49671d9db7a35cf19f1342eb3ee7c708cbc0c3a7f0aa8`.
This was one run on one GPU; GPU memory was sampled at 0.2-second
intervals and is not a guaranteed instantaneous peak. The input SHA-256
was `b9cdbdc91498a3082f4cabd44bde6a1a9ff9b60d458fc93ac904a5d0a537c072`;
the score-file SHA-256 was
`f4625a1f0d0f89f5f1eb6bf4aea58fd7b801998286e1443cb57ec03484e2957d`.
Small logs and CSVs are retained under
`results/raw/massive-data/20260930-chiamaka-50m-pca/`, outside Git.

A fresh-source 100-million-row by 96-column CUDA PCA run used a real
38.4 GB file, larger than Chiamaka's physical RAM. It completed in
237.054 seconds with 633,679,872 bytes of R peak RSS. The full streamed
output check passed. See
[the evidence](evidence/cuda-pca-100m-20261001/README.md) for identity,
memory sampling, and the synthetic-input limitations.

## Full-graph modularity scaling diagnostic

`benchmark_full_graph_modularity.R` runs the complete disk-backed KNN to
fuzzy-graph conversion, writes bounded blocks of synthetic community labels,
and compares full-graph modularity at two scan chunk sizes and against the
ring graph's closed-form modularity. The number of vertices must be divisible
by the number of communities. The input KNN file pair is generated by
`generate_knn_graph.py` in a unique directory;
the R runner also writes a `.weights.f32` file beside that input. Example:

```bash
python3 generate_knn_graph.py --vertices 1000000 --neighbors 10 \
  --prefix /path/to/private-run/ring
Rscript benchmark_full_graph_modularity.R \
  /path/to/private-run/ring 1000000 10 \
  /path/to/private-run/modularity /path/to/private-R-library 256MB \
  YOUR_SOURCE_ARCHIVE_SHA256 YOUR_INSTALLED_DLL_SHA256 10
```

The result CSV records graph size, each stage's elapsed time, modularity,
process high-water RSS, and the scan-buffer estimate. Mapped label pages can
appear in RSS, so the package's `memory_limit` is not an RSS ceiling. This
ring graph and its artificial labels are a throughput diagnostic, not a
community-detection or scientific-quality validation. The script does not
run full-graph Louvain, Leiden, or Walktrap. The runner refuses a package
binary whose SHA-256 differs from its declared DLL hash.

`benchmark_full_graph_louvain.R` uses the same fixed KNN input and
conversion stages, then times either the experimental CPU first local-moving
level or the memory-gated multilevel Louvain route and checks saved labels
against a fresh modularity scan. Select `multilevel` with the optional last
argument; omission selects `level0`.
It records mapped-state bytes, graph bytes, passes, and whole-process
peak RSS. The RSS high-water mark includes graph construction; it is not
an isolated Louvain peak or a memory-limit guarantee. The multilevel route
externally contracts the first-level graph, but its contracted graph must
fit the configured RAM budget. Neither mode tests Leiden or Walktrap.

```bash
Rscript benchmark_full_graph_louvain.R \
  /path/to/private-run/ring 1000000 10 \
  /path/to/private-run/louvain /path/to/private-R-library 256MB \
  YOUR_SOURCE_ARCHIVE_SHA256 YOUR_INSTALLED_DLL_SHA256
```

On 2026-10-01, the shuffled-block first level processed a synthetic
one-million-vertex ring with 20 million symmetric directed edges in
2.19 seconds, producing 56,732 communities and modularity 0.824008.
The earlier sequential scan took 1.37 seconds but collapsed the ring
into three communities with modularity 0.666657. This is why the bounded
row order was changed. The full graph pipeline's observed peak RSS was
404 MB in both runs, including fuzzy-graph construction; the graph file
was 168 MB and the mapped community state was 16 MB. Neither result is
a quality comparison with full multilevel Louvain or a billion-row test.
Small CSVs are retained in the private
`results/raw/massive-data/20261001-louvain-1m/` directory. The revised
source archive SHA-256 was
`e29298f29b31b15444113bf98a804fb67aeaba0b937a5af874f7884ec1a74e83`;
the installed DLL SHA-256 was
`0c6401fb44a79e7d755979185172198b354ffb92335589e8e420294791890d29`.
The Singularity image SHA-256 was
`54e9604d951ecb3d80f49671d9db7a35cf19f1342eb3ee7c708cbc0c3a7f0aa8`.
The focused ring regression test was added to the package source after
this measured archive; it does not change the native implementation.

The 2026-10-01 multilevel run used the same million-vertex, 20-million-edge
synthetic fuzzy ring. First-level modularity was 0.824008; multilevel
modularity was 0.996386 with 564 final communities. Membership construction,
fuzzy graph construction, and multilevel Louvain took 1.068, 1.956, and
3.476 seconds, respectively. Whole-process peak RSS was 410,087,424 bytes;
the memory gate estimated 96,155,648 bytes for the resident contracted
graph. The private evidence is `multilevel.csv` beside the earlier CSVs.
This establishes function and bounded memory on this synthetic input, not
billion-row scaling or accuracy on real data. Source archive SHA-256:
`6df493cbf47c6c72f83b80c42d7547dffe9b85124df07f5b33e6e4ba8761c35d`;
installed DLL SHA-256:
`aa5487e2cbb3ff5eba5ec4b52f75458fdc5081216b60a470b49aa868762e0754`.
The strict CUDA image hash remained
`54e9604d951ecb3d80f49671d9db7a35cf19f1342eb3ee7c708cbc0c3a7f0aa8`.
The installed-package massive test suite passed in that image in 9.711
seconds, with the unavailable-GPU-route and two-device tests skipped for
the expected hardware reasons. A real CUDA out-of-core PCA smoke test
reported CUDA sketch and projection and agreed with dense PCA on all
three checked components.

The [10-million-vertex Leiden check](evidence/leiden-10m-20261002/README.md)
uses 60 million directed fuzzy edges and an independent chunked modularity
calculation. Checkpointed and uninterrupted runs produced identical labels
across 11 levels with 308 and 313 MB peak process RSS, respectively. The
560 MB graph is larger than either process peak, but it still fits in the
test machine's 8 GB RAM; this is not an out-of-RAM graph result.
On a saved [MNIST70k fuzzy graph](evidence/mnist70k-leiden-pair-20261002/README.md),
file-backed and resident Leiden partitions had adjusted Rand indices
0.867-0.931 across three seeds; independently rescored modularity
remained within 0.0051. This is one-graph quality evidence, not a
matched speed comparison.
Separate seed-4 processes peaked at 109 MB RSS for the file-backed
route and 402 MB for the resident route on this same graph. This is
one measured local memory comparison, not an out-of-RAM graph result.

The shared-graph `massive_cluster(..., massive = "out_of_core_graph")`
entry point was validated separately on 2026-10-01. The no-vignette source
archive SHA-256 was
`36f9614d1055ddbf9b57d82da55de3858073d22fef5f4430af839a8964715d6c`,
and its strict-CUDA installed DLL SHA-256 was
`b9d9ef2defbcba506a1df3a8732da2dfb596cdf70fa99e9e6deb1ebf99d2d45d`.
The installed massive-data test filter passed in 9.932 seconds; it skipped
only the CUDA-unavailable route and two tests requiring multiple GPUs.
The normal vignette-complete archive, built from the same R and C++ source,
has SHA-256
`13b0bc5efa175e32d8ab5fb511ee3f849157babdc21f3213d932235fe31ae5a9`.
macOS `R CMD check --as-cran --no-manual` on that archive completed with
zero errors, zero warnings, and two notes (new submission and an existing
diagnostic pragma in the CUDA source). These tests do not validate
full-graph Leiden, Walktrap, or multi-GPU execution.

`verify_cuda_full_knn.R` is a strict companion GPU check. It compares
every neighbor ID and distance from file-backed sharded cuVS exact search
with the package's CPU streamed exact search. It requires CUDA capability,
CUDA backend/method metadata, more than one reference shard, and a
positive GPU memory estimate; it rejects a different installed DLL hash.
It hashes the source archive supplied on the command line instead of
accepting a caller-written hash as provenance.
Run the focused checks inside a CUDA-enabled container using fresh output
directories:

```bash
Rscript verify_cuda_full_knn.R PRIVATE_R_LIB RUN/knn \
  SOURCE_ARCHIVE.tar.gz INSTALLED_DLL_SHA256
Rscript verify_cuda_massive_tsne.R PRIVATE_R_LIB RUN/tsne \
  SOURCE_ARCHIVE.tar.gz INSTALLED_DLL_SHA256
```

On 2026-10-01, the verified binary below passed on Chiamaka's RTX 5060 Ti
for 2,048 rows, 32 features, ten neighbors, and eight CUDA shards.
Neighbor IDs matched on every row, with maximum distance discrepancy
`1.91e-6`. The locally copied CSV is
`cuda_full_knn_archive_verified.csv` in the
private experimental-massive evidence directory. This is a functional
GPU check, not a large-scale performance comparison or multi-GPU test.

The same installed binary completed a CUDA landmark UMAP smoke run on
20,000 synthetic rows and 96 features, using 1,000 landmarks and ten
neighbors. The complete call took 0.506 seconds; process peak RSS was
609 MB. The returned embedding and KNN backends were both `cuda`.
`verify_streamed_output.py` scanned all 20,000 output and KNN rows:
coordinates and distances were finite, and every landmark ID was valid.
The locally copied `cuda_landmark_umap_verified.csv` records the result.
This checks execution and file integrity, not layout quality or a
comparative speedup. The reported VRAM value is an estimate, not an
observed GPU-memory peak.

`verify_cuda_massive_tsne.R` checks the two-dimensional landmark t-SNE
route with a hash-verified binary. On the same Chiamaka build, 5,000
synthetic rows with 24 features and 500 landmarks completed in 0.523
seconds. The returned reference, KNN, and projection backends were CUDA;
all 5,000 saved coordinates were finite, and all 500 reference coordinates
were preserved exactly in the output. The copied evidence is
`cuda_landmark_tsne_archive_backends.csv`. This is an execution check
with short diagnostic iteration counts, not a quality comparison or
evidence of three-dimensional massive-mode CUDA t-SNE support.

On 2026-10-01, a Chiamaka diagnostic used one million synthetic ring
vertices with ten directed neighbors each. The fuzzy graph contained
20 million directed CSR entries (168 MB). Membership construction took
1.072 seconds, fuzzy symmetrization 1.958 seconds, and a full modularity
scan 0.067 seconds. Observed process peak RSS was 405 MB. The score
`0.899969` differed from the ring graph's independent analytic result by
`3.3e-16`. This is one untuned synthetic run, not a full community-detection
or billion-row benchmark. The source archive SHA-256 was
`8760f47a267605d43b937f4f7fcbda0b4bc07480bd403334002d3288c3b30512`,
the installed DLL SHA-256 was
`cdb1174b2f95b5c30c674e36be2e9deb4f660e54b80c8d6d4d4af7627221dad9`,
and the image SHA-256 was
`54e9604d951ecb3d80f49671d9db7a35cf19f1342eb3ee7c708cbc0c3a7f0aa8`.
The locally copied CSV is `modularity_verified_1m.csv` under the private
experimental-massive evidence directory. Earlier trial CSVs in that
directory were labeled with the final archive hash but loaded a different
private build; exclude those trial CSVs from analysis.

The same verified binary also completed a 10-million-vertex ring run with
100 million directed KNN edges. The resulting fuzzy CSR graph contained
200 million entries (1.68 GB); the label file occupied 40 MB. Membership
construction took 10.663 seconds, fuzzy symmetrization 27.588 seconds,
and each modularity scan 0.679 seconds. Observed process peak RSS was
434 MB, below the graph file size, while the modularity score matched
the independent closed form exactly. This establishes bounded-process-
memory scanning for this synthetic graph, not operation beyond total
system RAM or the availability of a full-graph clustering algorithm. The
locally copied result is `modularity_verified_10m.csv` in the same private
evidence directory; it records the source archive and DLL hashes above.

## Full-graph UMAP coordinate storage diagnostic

`benchmark_umap_layout.R` compares the native CPU optimizer's resident and
writable-mmap coordinate storage on the same synthetic CSR graph and
float32 initialization. Generate a CSR graph with
`generate_knn_graph.py --values weight --storage csr` and an initialization
with `generate_input.py --columns 2`. Use different output and CSV paths
for `memory` and `mmap`, then compare the two `.f32` outputs byte-for-byte.
Set `MASSIVE_TEST_SOURCE` to a source checkout for a local development run;
otherwise load the installed package. Example:

```bash
Rscript benchmark_umap_layout.R graph init.f32 1000000 3 \
  memory resident.f32 resident.csv 256
Rscript benchmark_umap_layout.R graph init.f32 1000000 3 \
  mmap mapped.f32 mapped.csv 256
cmp resident.f32 mapped.f32
```

The CSV records elapsed time and Linux `VmHWM`; use separate processes for
the two modes. On macOS, record peak RSS with `/usr/bin/time -l` instead.
The generated graph is directed and has synthetic weights, not fuzzy UMAP
memberships. This is a storage and optimizer diagnostic, not a quality or
publication benchmark. File-backed pages may still appear in process RSS.

An exploratory macOS run on 2026-09-30 used a dirty fastEmbedR 0.1 source
tree at commit `525fc2901fecb85ae6b331f2c21761b3c1aa5f16`, with two
neighbors per row, three epochs, and matching float32 initializations.
At 10 million rows, both modes wrote byte-identical 80 MB layouts. The
resident route took 9.684 seconds in the optimizer and reached 193.2 MB
peak process RSS; mmap took 9.482 seconds and reached 172.9 MB. A 180 MB
configured working budget rejected the resident route, while mmap
completed in 9.487 seconds and matched its output. These are single runs
on a synthetic directed graph, with no quality claim and no timing
uncertainty estimate. Their source tree was not immutable, so they must
not be used as publication results.

For `--repeat-chunk` PCA input, run `verify_periodic_pca.R` with the same
input dimensions, `--period` equal to the generator's `--chunk-rows`, and
`--model` pointing to the saved `.model.rds`. It compares means, singular
values, covariance eigen-equations, sampled scores, and repeated-row order
against independent dense PCA on one block. The eigen-equation check allows
valid rotations among tied principal components.
Set `--full-scan true` to compare every input and score block against that
independent period reference using bounded reads. Add `--csv` with a new
path to retain the pass/fail metrics for the run.

`verify_streamed_output.py` scans every row of a saved landmark layout and
its two KNN files through memory maps. It checks exact file sizes, finite
coordinates and distances, nonnegative distances, and one-based landmark
IDs within the fitted reference range. This is a format and integrity check,
not a neighborhood-preservation or embedding-quality metric.

`run_clustering.R` can reuse the saved CUDA query-to-landmark graph from a
landmark UMAP `.model.rds`. It builds only the small landmark graph on CPU,
then runs the package's existing Leiden, Louvain, or Walktrap method and
streams weighted community votes to disk. Its CSV reports clustering as
CPU and the reused KNN graph as CUDA, not as CUDA clustering.
`verify_cluster_output.py` scans all saved labels and confidence values,
checking file sizes, label bounds, finite confidence, and community counts.

## MNIST70k quality diagnostic

A fresh-source 2026-10-01 three-count CUDA sweep and matched-row quality
assessment are documented in
[`evidence/mnist-quality-current-20261001/README.md`](evidence/mnist-quality-current-20261001/README.md).
The subsequent CUDA resource-metadata correction has its own
[`evidence/cuda-landmark-resources-20261001/README.md`](evidence/cuda-landmark-resources-20261001/README.md).

`prepare_mnist.R` converts the complete MNIST float32 RData matrix to a
row-major `.f32` file in 5,000-row blocks and verifies sampled rows. Run
`run_scaling.R --mode umap --backend cuda --rows 70000 --columns 784
--neighbors 30 --landmarks 5000` and repeat with 10,000 landmarks, using
different output/CSV paths. Both runs require the same `--seed 4` and
validated package DLL. The saved `.model.rds` files retain the reference
fit and CUDA-built query-to-landmark KNN descriptors.

`score_mnist.R INPUT.RData MODEL.RDS OUTPUT_DIR R_LIBRARY` fits full-data
CUDA UMAP and scores both layouts on identical, fixed 2,000 MNIST rows.
Use a separate output directory for each landmark count. The expected
row-list SHA-256 for the 2026-09-29 diagnostic is
`e9fccf2835e8d36a703649fabdde42bbaacff76c8f591dee7eae7084e4f780fe`.
`run_refinement.R CUDA_MODEL.RDS OUTPUT.f32 R_LIBRARY` explicitly runs
50 CPU query-refinement epochs against fixed landmarks while reusing the
saved CUDA KNN; it does not reconstruct query-to-query neighborhoods.
Score the refined model with `score_mnist.R` in another output directory.
`diagnose_local_graph.R CUDA_MODEL.RDS INPUT.f32 OUTPUT.f32 R_LIBRARY`
tests a bounded 5,000-row CPU query graph with 500-row overlaps and 15
local neighbors. It retains fixed landmark coordinates and reuses the
saved CUDA landmark KNN, but is a diagnostic script, not a package API.
`score_local_graph_mnist.R` scores that output against the saved full
CUDA fit using the same fixed row list; it does not rerun the GPU fit.
`smoke_local_refine.R PRIVATE_LIBRARY OUTPUT_DIR` verifies the packaged
`massive_project_landmarks(local_refine = TRUE)` route with a CUDA reference
fit and CUDA landmark KNN. `run_local_api_mnist.R MODEL INPUT OUTPUT
PRIVATE_LIBRARY` reruns the MNIST70k local refinement through that API.
It rebuilds the identical CUDA KNN because older saved graph descriptors
do not record the source identity required by local refinement. Score its
new output with `score_local_graph_mnist.R` and the original fixed row list.
This local graph depends on input row order and does not represent all
query-to-query edges.
`summarize_mnist.R RESULT_DIR INPUT.RData` writes the compact quality CSV
and a consistent all-70k-point plot when the four score directories and
layout files are present under `RESULT_DIR` as named in that script. It
adds the local-graph result when its layout and score CSV are present.

These are exploratory quality checks. `run_scaling.R` records complete
landmark workflow time, whereas the refinement result's `elapsed_sec`
measures projection/refinement only. The full UMAP fit in `score_mnist.R`
is a separate diagnostic call. Do not divide these times to claim a
publication-quality speedup.

`smoke_native_reference.R` checks the experimental file-backed float32
reference handoff against the resident R-matrix route for CPU HNSW and
CUDA exact KNN. Set `FASTEMBEDR_TEST_LIB` to a private library containing
the source candidate and run it with NVIDIA passthrough; it fails when
CUDA is unavailable instead of counting a CPU fallback as success.
`benchmark_reference_memory.R PATH file|memory cpu|cuda ROWS` measures
index-build time for each reference route in a separate process. Use
`/usr/bin/time -v` to capture comparable peak process RSS; the input
must be a row-major `.f32` file with 96 columns and the declared rows.

## CUDA projection buffer diagnostic

`benchmark_cuda_projection_context.R` compares the existing per-batch
CUDA UMAP interpolation with the experimental retained-reference route.
Set `MASSIVE_TEST_LIBRARY` to the private source installation and
`MASSIVE_TIMING_OUTPUT` to a new CSV path. Optional
`MASSIVE_REFERENCE_ROWS`, `MASSIVE_BATCH_ROWS`, `MASSIVE_REPETITIONS`,
and `MASSIVE_TRIALS` select the workload. The script checks coordinate
agreement, warms both routes, alternates timing order across trials,
and writes every trial rather than only an aggregate.

On the GeForce RTX 5060 Ti, source archive SHA-256
`99e281d7c0255885343fc3ce57e1a4118894d430ee0073bb3387c1cc147a90b9`
inside image SHA-256
`54e9604d951ecb3d80f49671d9db7a35cf19f1342eb3ee7c708cbc0c3a7f0aa8`,
six trials of 500 batches with 16,384 queries, 30 neighbors, and a 2D
reference yielded the following median elapsed seconds per 500 batches:

| Reference rows | Per-batch | Retained | Per-batch / retained |
| ---: | ---: | ---: | ---: |
| 100,000 | 1.129 | 1.214 | 0.93 |
| 250,000 | 1.248 | 1.214 | 1.02 |
| 500,000 | 1.503 | 1.214 | 1.24 |
| 1,000,000 | 1.896 | 1.212 | 1.56 |

These are kernel-interface microbenchmarks, not full embedding timings.
At 100,000 reference rows but only 1,024 queries per batch, the retained
route was 1.75 times faster. The package therefore selects the retained
route when reference-transfer bytes exceed planned batch-transfer bytes,
and reports that selection. Neither route is a universal speedup. The
CSV evidence is retained outside Git under the private massive-validation
result directory.

## Full KNN graph storage diagnostic

`generate_knn_graph.py` writes a deterministic directed, non-self KNN file
pair in bounded blocks. It requires NumPy and checks free disk space before
writing. With a private installation of the source candidate, run:

```bash
python3 generate_knn_graph.py --vertices 1000000 --neighbors 30 \
  --chunk-rows 100000 --prefix /path/to/private-run/graph
/usr/bin/time -v Rscript benchmark_graph_source.R \
  /path/to/private-run/graph 1000000 30 stream \
  /path/to/private-R-library /path/to/private-run/graph_stream.csv
```

Repeat with `mmap` and a different CSV. The Linux CSV records R's own
baseline and final `VmHWM` plus the difference; CUDA-linked package loading
has substantial baseline RSS. `/usr/bin/time -v` may also reflect
Singularity startup.
The script validates the full
graph through bounded sequential reads in either mode, times bounded reads
at the first, middle, and last rows, and checks
their known neighbors. `/usr/bin/time -v` reports peak process RSS on
Linux. This measures file-backed graph import and reading only; it does
not benchmark ANN search, fuzzy UMAP, or community detection.

The 2026-09-30 exploratory run used the 0.1 source archive with SHA-256
`a492492f9c18710c4f3c18b4c31c1183867064d1606d98dc36e48f4cad6b19f6`.
On macOS, a 1,000,000-vertex, 30-neighbor (240 MB) graph validated all
30 million edges with peak process RSS of 88 MB for stream reads and 93 MB
for mmap reads. Both modes validate sequentially; mmap applies only to the
sampled edge reads. The one-shot validation times, 0.956 and 0.126 seconds,
are not comparable speed estimates because OS caching differed. The same
archive installed in strict CUDA mode inside Chiamaka image SHA-256
`54e9604d951ecb3d80f49671d9db7a35cf19f1342eb3ee7c708cbc0c3a7f0aa8`;
its focused graph tests passed. On that Linux installation, both access
modes scanned 30 million edges in 0.112 seconds after filesystem caching.
The R process started at 324,996 KB (stream) or 325,208 KB (mmap) of
`VmHWM` and reached 335,220 KB or 335,432 KB, respectively: 10,224 KB
added in either run. These are one-shot, cached-file measurements, not
search or optimizer timings. They show storage correctness and bounded
validation RSS, not a full-data embedding or clustering capability.

The same generator can write externally supplied weights rather than
distances. Keep these outputs separate from distance graphs:

```bash
python3 generate_knn_graph.py --vertices 1000000 --neighbors 30 \
  --chunk-rows 100000 --values weight \
  --prefix /path/to/private-run/weighted_graph
Rscript benchmark_graph_source.R \
  /path/to/private-run/weighted_graph 1000000 30 stream \
  /path/to/private-R-library /path/to/private-run/weighted.csv weight
```

The weighted-path 0.1 source archive has SHA-256
`e1447ada4b7cf775a68d2daa64471da5ce44e4f016773af7da85f10b92af2057`.
Its private installation in the same Chiamaka image passed the focused
graph tests. One million vertices and 30 neighbors occupied 240 MB on
disk. Stream and mmap read modes validated 30 million weights in 0.139
and 0.133 seconds after filesystem caching, adding 10,912 and 10,948 KB
to R's `VmHWM`. These are single I/O observations; the generated weights
are synthetic and are not fuzzy UMAP memberships or quality evidence.

For variable-degree weighted CSR storage, add `--storage csr`. This creates
`.offsets.u64`, `.indices.u32`, and `.weights.f32`; alternate rows have
`k` and `k - 1` neighbors, respectively. Within each row, neighbor IDs
are sorted and unique. The weights are synthetic and directed.

```bash
python3 generate_knn_graph.py --vertices 1000000 --neighbors 30 \
  --chunk-rows 100000 --values weight --storage csr \
  --prefix /path/to/private-run/csr_graph
Rscript benchmark_graph_source.R \
  /path/to/private-run/csr_graph 1000000 30 stream \
  /path/to/private-R-library /path/to/private-run/csr_stream.csv csr
```

Repeat with `mmap` and a different CSV. The source archive SHA-256 for this
check is `74cafffcede6b6d22e3255c96560474f20f4b8ba310f4b2537207ae8bcb92686`.
It passed macOS `R CMD check --as-cran --no-manual` with zero errors,
zero warnings, and two unrelated notes. It installed with strict CUDA
configuration in the Chiamaka image identified above; the CSR check itself
used CPU file reading. The 1,000,000-vertex fixture held 29.5 million
edges in 244 MB. Both stream and mmap modes validated all rows and edges
with bounded reads. In these one-shot cached-file observations, validation
took 0.083 and 0.076 seconds, and R's process `VmHWM` increased by 7,348
and 7,420 KB, respectively. This establishes format and memory behavior
for graph import only, not fuzzy UMAP construction, ANN, embedding, or
clustering performance.

## Full-data ANN routing diagnostic

An [instrumented posting-batch check](evidence/posting-batch-io-20261002/README.md)
records logical posting bytes read in addition to the prior worst-case
bound; it does not measure physical SSD traffic.
A [grouped-query check](evidence/posting-query-order-20261002/README.md)
uses saved original row IDs for correct self-exclusion and measures the
read reduction from processing queries in posting order. The full graph
writer can use that order when explicitly requested.

An independent 100-million-row virtual-source PCA check is documented in
`evidence/virtual-pca-100m-20261001/`. It tests bounded-memory
computation and large row offsets, not disk throughput.
A [70-million-row physical-input PCA check](evidence/physical-pca-over-ram-20261002/README.md)
uses a non-sparse 8.96 GB file on an 8 GB Mac, records peak process RSS,
and verifies every saved score row.

For a repeated-block wide input, `verify_wide_pca_fit.R` runs the full
experimental PCA call from a private installed library. It requires the
requested backend and the exact covariance route, checks the complete
file-backed score output in bounded reads, and compares its mean,
eigenvalues, and eigen-equation residual against an independent covariance
from one input period. It records package version and native DLL MD5.
Run it under `/usr/bin/time -v` on Linux to record process peak RSS, and
sample `nvidia-smi` separately for peak VRAM. Do not infer peak VRAM from
the package's buffer estimate or call a CUDA run validated from a CPU smoke
test. A strict build and source-archive hash remain separate release gates.

The package also exposes EXPERIMENTAL `massive_coarse_postings()` to group
file-backed float32 rows by supplied centers. The native builder makes two
bounded input passes and writes original row IDs and 64-bit posting offsets.
`benchmark_package_postings.R` generates a deterministic input and checks
representative feature/ID pairs from every nonempty list. On an Apple M3
with 8 GB RAM, the dirty-source fastEmbedR 0.1 archive with SHA-256
`9189004cc95ecdf7c0c1c49159161069ce82ea3749699d68e14f4be705c5451e`
gave 0.108 seconds for 1 million by 8 and 1.085 seconds for 10 million by 8
rows with 16 supplied centers and four workers. The 10-million-row run
used a 320 MB input, wrote 360 MB of postings, and reached 238 MB process
peak RSS (`/usr/bin/time -l`). A separate complete ID check found each of
the 10 million rows exactly once. These are grouping times, not ANN search
times. Both datasets fit in machine RAM; search, recall, and recovery remain
unproven. The package's `128MB` setting budgets algorithm buffers and does
not cap whole-process RSS. The small result CSVs are in
`evidence/package-postings-20261001/`.

`diagnose_ann_routing.R` tests whether a small random-anchor or trained
k-means-centroid routing layer could make disk posting lists selective.
It assigns each input row to its nearest one to eight anchors, evaluates
exact distances for sampled query rows, and reports recall at several
numbers of probed lists. The entire input is scanned once for this
diagnostic.
`diagnostic_seconds` is **not** a production-index search time or a
full-graph construction time.

```bash
Rscript diagnose_ann_routing.R \
  /path/to/input.f32 NROW NCOL /path/to/private-run/routing.csv \
  64 32 4096 15 kmeans 2
```

The arguments after the CSV are anchor count, sampled query count, input
chunk rows, `k`, optional anchor method (`random` is the default), and
replication count (`1` is the default).
K-means trains on at most 4,096 sampled rows with a 256 MB sample budget;
its iteration count is reported. The output includes sampled mean/minimum
recall, unique-candidate fraction, logical posting-read fraction,
maximum list fraction, empty-list count, and main scan bytes. The
posting-read fraction counts duplicated rows across selected lists;
it is a projected scan volume, not measured SSD traffic. This script
does not build a persistent index. Compare several input
shapes before adopting any routing policy. On deterministic 20,000-row
synthetic pilots with 32 queries and `k = 15`, eight of 64 random lists
gave 100% sampled recall while scanning 12.8% of candidates on a
16-feature clustered mixture. On diffuse 96-feature Gaussian data,
32 of 64 random lists scanned 79.4% for only 94.4% mean recall.
Training 64 centroids raised mean recall to 99.6% at 32 probes, but
scanned 94.7% of candidates. With 128 trained centroids, 64 probes
scanned 91.0% for 99.2% mean recall. The largest random-anchor list
held 14.6% of diffuse rows versus 1.6% for an even 64-way split.
With 64 trained centroids and two copies per row, 16 probes recovered
97.5% mean recall but required a projected 129.6% full posting scan.
Four copies and 16 probes recovered all sampled neighbors but required
258.5% of a full posting scan.
This pilot rejects single-assignment centroid routing as a universal
full-data default; it does not assess balanced or replicated posting
lists at larger scales or SSD graph search. The CSVs and inputs remain
private temporary
files, not publication benchmarks.
