# Source-locked JSS and Deep1B campaign

This launcher submits three independent campaigns: paired JSS with NOMAD,
extended JSS, and the Deep1B matrix. The JSS suite uses the datasets and
method contract in `../jss-review-validation/`; the Deep1B matrix uses
`../massive-data/deep1b/`. The latter has 1M, 10M, 50M, and
100M file-backed windows, ordinary 1M controls, 4/8/16 CPU workers, and
1/2/4 L40S requests. See `submit_matrix.sh --plan` for the exact list.
NOMAD is a separate contrastive projection in the supported JSS CUDA
comparisons, not a UMAP/t-SNE alias or a Deep1B file-backed method.

## Without Slurm

Install matching source archives of `gpuinfo` (>= 0.2.0), `faissR`
(>= 0.99.51), and `fastEmbedR` into one R library. Run these local checks:

```sh
Rscript ../massive-data/deep1b/test_run_full_graph_smoke.R
Rscript ../massive-data/visualization/test_render_full_layouts.R
python3 ../massive-data/deep1b/test_submit_matrix.py
```

The first check creates a 1,000-row float32 input, fits file-backed PCA,
UMAP, Leiden, and Louvain on every row, verifies the output lengths, and
removes only its own temporary directory. It does not require Deep1B or
Slurm. The plotter check uses a synthetic all-row layout. These smoke tests
verify code paths, not Deep1B performance or GPU correctness. The same
`run_full_graph.R` accepts a `.fbin` source, row count, output directory,
and explicit backend for non-Slurm runs. GPU runs additionally require
the documented CUDA/cuGraph dependencies and physical device auditing.

## On UCT HPC

Place this repository's `benchmarks/linux/jss-review-validation/`,
`benchmarks/linux/massive-data/deep1b/`,
`benchmarks/linux/massive-data/visualization/`, and this `unified/`
directory under `/scratch/firenze/NN/benchmark_scripts/` at the
corresponding relative paths. Keep the original `Data/` inputs. Transfer
the source-locked `fastembedr_cuda.sif` separately, then add its verified
SHA-256, package source SHA-256, and patch identity to
`jss-review-validation/common/image_source_identity.csv`; regenerate its
`FILES.sha256` manifest. Check the planned matrix before submitting:

```sh
cd /scratch/firenze/NN
bash benchmark_scripts/massive-data/deep1b/submit_matrix.sh --plan
bash benchmark_scripts/unified/submit_from_login.sh
```

The login helper reads `purequota` (or `myquota` where it is an executable)
and submits a short CPU launcher. On UCT, `myquota` is only an interactive
alias, so noninteractive submissions use `purequota`.
Container checks and campaign staging run on a compute node. JSS submits
one strict CPU and one strict CUDA preflight first, then independent paired
NOMAD and extended campaign controllers after both pass. A GPU quota
refusal schedules a small CPU retry controller; it does not stop the
independent Deep1B CPU jobs. Deep1B resumes unsubmitted GPU lanes the
same way, without duplicating jobs recorded in its ledger. The unified
launch status records staging, not final benchmark success. Within a
Deep1B hardware lane, 1M and 10M are independent; 50M/100M cases wait
for earlier same-lane jobs to finish
and release scratch. These storage-only dependencies use `afterany`, so a
failed smaller case does not suppress larger independent evidence. The
16-CPU 100M case also waits for the 4-CPU 100M case. The 2-GPU 100M
case waits for the 1-GPU 100M case, and the
4-GPU 100M case waits for the 2-GPU 100M case. These cross-lane
dependencies cap concurrent large payloads under the
explicit quota reserve. Jobs, identities, dependencies, and launch failures
are recorded in `fastEmbedR-results/unified/` and the Deep1B matrix ledger.
If a previous launcher stopped after submitting some Deep1B jobs, resume
its existing matrix instead of rerunning `submit_from_login.sh`:

```sh
MATRIX_ROOT=/scratch/firenze/NN/fastEmbedR-results/massive-data
MATRIX=$MATRIX_ROOT/deep1b_matrix/MATRIX_RUN_ID/jobs.tsv
bash benchmark_scripts/massive-data/deep1b/submit_matrix.sh \
  --resume "$MATRIX"
FASTEMBEDR_IMAGE_SHA256=IMAGE_SHA256 \
  bash benchmark_scripts/unified/stage_jss.sh \
  /scratch/firenze/NN/fastEmbedR-results/unified/UNIFIED_RUN_ID
```

Use the actual run IDs and verified image hash. Matrix resume checks the
image identity, reuses every recorded job, and records the new scheduler
source hash. A GPU quota refusal creates a dependent CPU retry job; if a
four-GPU request still fails after all other GPU jobs finish, it stops
and reports the account limit instead of looping.

After jobs finish, make a compact `methods.csv`:

```sh
python3 benchmark_scripts/massive-data/deep1b/summarize_matrix.py \
  "$LEDGER/jobs.tsv"
```

It preserves
successful methods from partial jobs and names unsupported clustering
routes explicitly; it does not read the full embeddings into RAM.
The kNN row includes the observed recall, the explicit 0.99 gate result,
the count of sampled rows below target, and the per-shard HNSW settings
file when that CPU route was used. The full 100M CPU4 case has a 32 GB
Slurm RAM cap, below its 38.4 GB input matrix. It supports a beyond-RAM
claim only if that fit passes with every output row present; the other
cases use a 64 GB cap. The per-case limit appears in both ledgers.

## Publication gates

Report per-method outcomes, not just Slurm completion. Required evidence
includes complete row counts, observed exact-neighbor recall and effective
settings, staged timing, process RSS, per-GPU UUID memory, generated SSD
peak, and all-row plots. File-backed CUDA clustering currently requires
2-4 GPUs plus enough combined VRAM for the distributed graph. A rejected
50M/100M clustering fit must remain visible as a feasibility failure; it
cannot turn an independent PCA/t-SNE/UMAP output into a claimed cluster
result. Deep1B has no supplied class labels, so its plots are unlabelled
all-row density renderings. Labeled quality comparisons belong in JSS.

Transfer metrics, audits, provenance, and figures for review. Omit `.f32`,
`.u32`, `.rds`, `embedding.csv`, and container images from the result copy; they
are generated payloads, not manuscript figures. Delete intermediate HPC
payloads only after matching copied checksums and a passing stage audit.
Do not delete original BigANN inputs or unverified results.
