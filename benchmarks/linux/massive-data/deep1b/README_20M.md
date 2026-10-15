# Deep1B 20-million-row campaign

This campaign replaces the previous 100M full-graph plan. It fits the
same Deep1B row window (starting at source row 1,000,001), uses seed 4,
and never fits more than 20 million rows. It does not use landmark
projection and never calls a landmark fit a full-graph result.

## Cases and honest capability boundaries

Run `bash submit_20m.sh --plan` to inspect all 18 independent jobs.

| Rows | File-backed CPU | File-backed CUDA | In-memory classic |
| ---: | --- | --- | --- |
| 1M | PCA, full KNN, t-SNE, UMAP, Leiden at 1/4/8 requested CPU workers | PCA, full KNN, t-SNE, UMAP on one and two GPUs | PCA, t-SNE, UMAP on CPU and one GPU |
| 10M | Same CPU workflows at 1/4/8 | Same workflows on one and two GPUs | Not submitted |
| 20M | Same CPU workflows at 1/4/8 | Same workflows on one and two GPUs; separate two-GPU PCA audit | Not submitted |

The 1/4/8 CPU settings affect streamed PCA, KNN, affinity, memberships,
and CPU t-SNE optimization. Full-graph UMAP and Leiden optimization
still run with one worker. The `effective_cores` column in `stages.csv`
records this explicitly. These are whole-workflow scaling comparisons,
not UMAP/Leiden optimizer speedup claims.

The two-GPU full-graph runs exercise the package's coordinated KNN,
UMAP, and t-SNE routes. Their correctness, quality, and speed remain
experimental until completed results are audited. A requested device
set must match the fit metadata and monitored hardware UUIDs. PCA fitting
rows, KNN shard bytes, and UMAP/t-SNE edge counts must also be positive
on both GPUs;
mere two-GPU allocation is insufficient. Classic in-memory methods do not
have a two-GPU route. The launcher records other exclusions in
`unsupported_routes.tsv`. A 20M x 96 float32 input is 7.68 GB, so
this campaign does **not** prove input larger than one L40S GPU's RAM.

Each full-graph KNN fit also measures exact recall on 128 evenly
spaced query rows. `knn.csv`, `knn_audit_rows.csv`, and distinct
`hnsw_settings.csv` configurations report the observed recall and
effective build/search settings. This is a sampled audit, not a
full-graph recall guarantee or an independent tuning holdout.
KNN stage time includes the exact-reference audit.
An execution `PASS` with a recall warning is not a 0.99-quality pass.

Each fit records process peak RSS, stage seconds, quality on a fixed
4,096-row sample, sampled per-device VRAM for CUDA, the logical-ID to
hardware-UUID map, per-device work and optimizer stage times, and
sampled peak scratch allocation under `work/` and `results/` in
`disk_peak.csv`. The disk peak excludes the original input and image
hard link. The campaign also saves full-row
grayscale density PNGs. The PNGs rasterize every fitted output row;
no invented class labels or Leiden communities color the embeddings.
The Leiden barplot shows sizes from a separate 10,000-row sample.
Binary embeddings and intermediate graphs are removed only after
scoring and figure generation. The original `.fbin` is never removed.
Inspect `audit.json`; a queued or failed job is not a benchmark result.

## Launch on UCT Slurm

First stop the obsolete full-graph jobs. Do not cancel other projects:

```bash
cd /scratch/firenze/NN
mapfile -t ids < <(
  squeue -h -u "$USER" -o '%A|%j' |
    awk -F '|' '$2 ~ /^feR_fg_(deep|turing)_(cpu|cuda)$/ {
      print $1
    }' | sort -u
)
printf 'Old full-graph jobs: %s\n' "${ids[*]:-none}"
if ((${#ids[@]})); then scancel "${ids[@]}"; fi
squeue -u "$USER"
```

From the Mac, copy *code only*, not input or prior results:

```bash
SRC=/Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/massive-data
HOST=01481067@hex.uct.ac.za
REMOTE=/scratch/firenze/NN/benchmark_scripts/massive-data
ssh "$HOST" "mkdir -p '$REMOTE/deep1b'"
rsync -av --exclude='__pycache__/' "$SRC/deep1b/" \
  "$HOST:$REMOTE/deep1b/"
rsync -av "$SRC/visualization/render_full_layouts.R" \
  "$HOST:$REMOTE/visualization/"
```

Submit from the HPC login node; no interactive allocation is needed:

```bash
cd /scratch/firenze/NN
bash benchmark_scripts/massive-data/deep1b/submit_20m.sh --plan
bash benchmark_scripts/massive-data/deep1b/submit_20m.sh
```

The launcher checks the exact image SHA-256 and completed Deep1B input
manifest. If `myquota` is unavailable, set `DEEP1B_QUOTA_FREE_BYTES`
to your verified free personal `/scratch` quota, in bytes. It reserves
212.344 GB for the sum of stage-peak bounds for all 18 independent jobs
under the default shared-KNN strategy, requiring about 265.43 GB free
with a 20% margin. This excludes the
existing input and image. The UMAP stage sorts vertex buckets directly
from KNN distances, without a directed-membership file. Each fit reclaims
t-SNE affinity and KNN files after their last consumers finish. It also
reclaims the fuzzy CSR graph after UMAP and CPU Leiden finish, and
retired Leiden levels while retaining the final label file;
`reclaimed_payloads.csv` records the actual bytes. Bucketed UMAP graph
sorting does not yet support checkpoint or resume.
For an opt-in lower-SSD combined route, set
`DEEP1B_REBUILD_KNN_FOR_UMAP=1` before `submit_20m.sh`. The first KNN
pair is consumed during t-SNE graph construction, then kNN is rebuilt
and independently audited before UMAP. Expect a second KNN runtime;
the default shares one build at higher peak SSD use. The lower-SSD
plan sums to 175.144 GB, requiring about 218.93 GB free with the same
margin. See [README.md](README.md) for the
one-billion-row planning bound and smoke-test result.
For `DEEP1B_FIT_MODE=full_tsne`, the KNN pair is removed immediately
after affinity construction, before t-SNE optimization. This does not
lower the graph-construction peak, but reduces disk held during fitting.
Check `disk_peak.csv` for measured allocation, not the preflight bound.
Once reclaimed, an earlier stage must be rebuilt to rerun it; the
completed embeddings remain available until final pruning. A later
graph-dependent rerun must rebuild the fuzzy graph.
No job depends on an L40S queue. Slurm may
still defer jobs for priority or physical resources. CPU jobs request
their actual 1/4/8 cores; CUDA jobs request one or two L40S devices.
The launcher refuses to overlap an active older `feR_fg_` campaign.
Override account and partition names with `DEEP1B_CPU_ACCOUNT`,
`DEEP1B_CPU_PARTITION`, `DEEP1B_GPU_ACCOUNT`, and
`DEEP1B_GPU_PARTITION` when using a different Slurm site.

The printed `jobs.tsv` maps every job ID to its output directory.
After completion, copy only evidence and images, excluding the large
BigANN input and binary intermediate files:

```bash
HOST=01481067@hex.uct.ac.za
SRC=/Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/massive-data
HPC_HOST="$HOST" bash "$SRC/deep1b/copy_small_results.sh"
```

## Without Slurm

The fitting script is ordinary R and can run with a local fastEmbedR
installation. For a 2,000-row correctness smoke test, create a
structured float32 `.fbin` and use a local output tree:

```bash
SUITE=/path/to/fastEmbedR-extra/benchmarks/linux/massive-data
BASE=/path/to/local-work
CAMPAIGN="$BASE/fastEmbedR-results/massive-data/deep1b/smoke"
mkdir -p "$CAMPAIGN" "$BASE/Data/BigANN/deep"
INPUT="$BASE/Data/BigANN/deep/smoke.fbin"
Rscript "$SUITE/deep1b/make_smoke_fbin.R" "$INPUT"
DEEP1B_SMOKE=1 DEEP1B_FIRST_ROW=1 DEEP1B_CPU_CORES=1 \
  Rscript "$SUITE/deep1b/run_full_graph.R" \
  "$INPUT" deep cpu 2000 "$CAMPAIGN"
CASE="$CAMPAIGN/results/cpu_tsne_2000_fullgraph"
Rscript "$SUITE/deep1b/score.R" "$INPUT" \
  "$CASE/output.f32" 2000 2 "$CASE" deep 1
Rscript "$SUITE/visualization/render_full_layouts.R" \
  "$BASE" deep 2000 "$CAMPAIGN/figures" \
  "$CAMPAIGN" cpu_tsne_2000_fullgraph
```

The same call can use `DEEP1B_CPU_CORES=4` or `8`; use a distinct
campaign directory per run. CUDA needs fastEmbedR built with CUDA and
`DEEP1B_GPU_DEVICES=0`; use devices `0,1` with `DEEP1B_FIT_MODE=full`
to check coordinated multi-GPU KNN and optimizers. The synthetic data
is a functional
check, never manuscript evidence. To repeat the real-data experiment
without Slurm, download Deep1B as documented in `../README.md`, use
the complete `.fbin` input, omit `DEEP1B_SMOKE`, and run the same R
script with rows 1M, 10M, or 20M. The Slurm shell wrapper adds
source/image locking, peak-memory sampling, quality, figures, audit,
and safe payload cleanup; reproduce those steps when reporting results
from a non-Slurm machine.
