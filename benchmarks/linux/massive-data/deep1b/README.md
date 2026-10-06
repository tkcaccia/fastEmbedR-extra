# Deep1B and Turing disk-backed benchmark (experimental)

This lane uses the completed Yandex DEEP 1B or Microsoft Turing-ANNS file
directly. It does **not** copy prefixes or load the full matrix into R RAM.
`massive_matrix()` opens
the `.fbin` descriptor; the benchmark selects a disk-backed view of its first
`rows` observations. The GPU routes stage bounded chunks. The first-row
prefixes are reproducible but are not independent samples of all 1B vectors.
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
| `scale` | 1 million | CPU/CUDA PCA, KNN, landmark UMAP/t-SNE; 2-GPU PCA and landmarks | Stage time, RSS, disk I/O, GPU placement |
| `boundary` | 100 million | CPU/CUDA PCA and landmarks; 2-GPU PCA | Test 38.4/40 GB of selected input under an 8 GB Slurm RAM cap |
| `billion` | 1 billion | 2-GPU PCA and landmark UMAP/t-SNE | Explicit opt-in only; no default billion-row job |

`pilot` and `scale` use `k=30`, 4 CPU workers, seed 4, 2 PCA components,
and 1,000 or 5,000 landmarks. `boundary` and `billion` use 10,000 landmarks.
t-SNE requests 250 early plus 750 normal optimization iterations for the
landmark fit and 250 projection iterations. The full KNN cases retain the
package's CPU HNSW-sharded or CUDA cuVS IVF-sharded route; they do not use
NN-descent. KNN recall is measured on 16 exact-reference rows. It is an
observed sample statistic, not a guarantee of 0.99 recall for every row.

The 512-row quality sample uses the same deterministic, dispersed row IDs
for every fitting method at a given prefix size. Trustworthiness and local
neighbor preservation are measured **within that sample**, not against all
1B neighbors. Neither input has labels in this lane, so label KNN accuracy
is not reported. `metrics.csv`, `quality.csv`, `quality_row_ids.csv`,
`time.txt`, and `status.tsv` are retained per case. `metrics.csv` includes
observed process peak RSS and `/proc/self/io`; `/usr/bin/time -v` provides
an independent MaxRSS. The selected-input byte count is distinct from the
physical 384/400 GB file size. Plot/CSV output is small; no dense coordinate
CSV is written. GPU VRAM in the package record is an estimate, not an
observed peak; this lane does not yet establish GPU peak-memory use.

## Launch on the HPC

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
bash benchmark_scripts/massive-data/deep1b/submit.sh pilot
```

Run Turing separately with the same case registry:

```bash
bash benchmark_scripts/massive-data/deep1b/submit.sh pilot turing
```

The default remains Deep1B. Turing results are stored under
`fastEmbedR-results/massive-data/turing/`, separate from Deep1B's
`fastEmbedR-results/massive-data/deep1b/`. The input, dataset identity,
image, and source checksums are saved in each campaign. Wait for the current
Deep1B campaign to finish before syncing revised scripts to the HPC, so its
pending GPU jobs use the same source as its completed CPU jobs.
The launcher first checks that the image accepts checkpointed KNN on a
file-backed row view. The image used for the 2026-10-06 Deep1B pilot does
not; it must be rebuilt with the package fix before another pilot launch.
The preflight fails before submitting jobs when that contract is missing.

Inspect every `status.tsv` and the recorded package DLL hash before moving
to the next phase. Launch phases separately; no CPU case waits for a GPU
case. The default Slurm throttle is four CPU tasks, two one-GPU tasks, and
one two-GPU task. A two-GPU case requests two L40S cards. Override with
`DEEP1B_CPU_THROTTLE`, `DEEP1B_GPU_THROTTLE`, or
`DEEP1B_GPU2_THROTTLE`, and set accounts/partitions with
`DEEP1B_CPU_ACCOUNT`, `DEEP1B_CPU_PARTITION`, `DEEP1B_GPU_ACCOUNT`, and
`DEEP1B_GPU_PARTITION`; use `DEEP1B_BASE` for another project root.
Set `FASTEMBEDR_EXPECTED_VERSION` and, when known,
`FASTEMBEDR_EXPECTED_DLL_SHA256` to reject an unintended package build.

```bash
bash benchmark_scripts/massive-data/deep1b/submit.sh scale
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

## What this does not establish

This lane does not run a **full 1B KNN graph** or a full 1B UMAP/t-SNE
optimizer. The largest cases use landmark projection, which still writes one
result per observation. Multi-GPU cases test distributed PCA moments or
landmark projection, not multi-GPU full-graph optimization. A separately
scoped checkpoint/interruption test is needed before claiming recovery at
100M/1B rows. Repeated fixed-seed timings, full-dataset quality metrics,
and comparisons with other implementations remain separate experiments.
