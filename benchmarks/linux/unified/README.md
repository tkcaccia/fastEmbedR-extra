# Source-locked JSS and Deep1B campaign

This launcher is archived and rejects execution. Its historical design
submitted three components under one source-locked campaign: paired JSS
with NOMAD, extended JSS, and the Deep1B matrix.
Each component has its own job ledger, while the unified root records their
paths and one aggregate verdict. The JSS suite uses the datasets and method
contract in `../jss-review-validation/`; the Deep1B matrix uses
`../massive-data/deep1b/`. The current matrix has independent 1M and 10M
file-backed windows, ordinary 1M controls, 4/8/16 CPU allocations, and
one-/two-L40S requests. See `submit_matrix.sh --plan` for the exact cases.
The 100M and 1B two-GPU cases are deferred until end-to-end resume and
quota-aware storage gates pass; neither is submitted by this launcher.
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

This unified campaign includes file-backed scientific work and cannot run
on the UCT HPC, including after the separate GPU pause is lifted. Every
local submission and controller entrypoint rejects execution. No deployed
source-locked script has been replaced. Use the resident one-case candidate
for future HPC calculations, subject to its own qualification gates.

Read-only inspection remains available. Use `submit_matrix.sh --plan` to
inspect intended lanes, then examine archived `jobs.tsv`, `audit.json`,
`failures.tsv`, and source/image manifests. A completed Slurm job alone
does not pass a method audit. The paired JSS campaign ended with `WARN`;
the extended campaign has no passing final audit, and the Deep1B matrix
contains failed and missing case audits. The Turing file-backed arm is
unverified because its source input is absent. No deferred GPU retry is
scheduled by the revised Deep1B matrix launcher.

Run the aggregate audit during the campaign and after all jobs finish:

```sh
ROOT=/scratch/firenze/NN/fastEmbedR-results/unified/UNIFIED_RUN_ID
python3 benchmark_scripts/unified/audit.py "$ROOT" --write
```

It reads both JSS final audits and every planned Deep1B case audit. Only
three passing components with one image identity yield `PASS`. Missing
results are `INCOMPLETE`, failed results or mismatched identities are `FAIL`,
and warnings such as missed recall gates are `WARN`. Any non-PASS status
returns a nonzero exit code. Neither submission nor Slurm `COMPLETED` is a
pass for this HPC core campaign.

For compact, separate Deep1B method ledgers, run locally or on the HPC:

```sh
python3 benchmark_scripts/massive-data/deep1b/summarize_matrix.py \
  CPU_JOBS.tsv --backend cpu --output cpu_methods.csv
python3 benchmark_scripts/massive-data/deep1b/summarize_matrix.py \
  CUDA_JOBS.tsv --backend cuda --output cuda_methods.csv
python3 benchmark_scripts/massive-data/deep1b/compare_matrix.py \
  CPU_JOBS.tsv CUDA_JOBS.tsv --output comparison.csv
```

These read-only commands preserve
successful methods from partial jobs and names unsupported clustering
routes explicitly; it does not read the full embeddings into RAM.
The comparator refuses mismatched image/source identities and reports
an empty ratio for missing, failed, or recall-ineligible cases.
The kNN row includes the observed recall, the explicit 0.99 gate result,
the count of sampled rows below target, and the per-shard HNSW settings
file when that CPU route was used. The current matrix requests 64 GB per
case. Its 10M-row input window is 3.84 GB, so it cannot prove that the
source matrix exceeds host RAM. A beyond-RAM claim requires a
separately audited RAM boundary case with an input larger than the enforced
limit and every output row present.

## Publication gates

The unified HPC core does not yet run every analysis reserved in the
manuscript. In particular, it lacks a matched multi-seed full-versus-landmark
study, an enforced beyond-RAM full UMAP/t-SNE case, and full restart
equivalence. A separate five-million-row Deep1B HNSW pilot now has
disjoint tune/holdout and insertion-order observations, but not a Turing
holdout or billion-row validation. Three- and four-GPU arms are outside
the revised protocol. Metal and macOS results require a separate host.
Track these gaps in
`../../../analysis/JSS_EVIDENCE_GATES_20261016.md`; do not label the paper's
entire evidence set complete from a three-component HPC `PASS` alone.

Report per-method outcomes, not just Slurm completion. Required evidence
includes complete row counts, observed exact-neighbor recall and effective
settings, staged timing, process RSS, per-GPU UUID memory, generated SSD
peak, and all-row plots. File-backed CUDA clustering currently requires
multiple GPUs plus enough combined VRAM for the distributed graph. A rejected
fit must remain visible as a feasibility failure; it
cannot turn an independent PCA/t-SNE/UMAP output into a claimed cluster
result. Deep1B has no supplied class labels, so its plots are unlabelled
all-row density renderings. Labeled quality comparisons belong in JSS.

Transfer metrics, audits, provenance, and figures for review. Omit `.f32`,
`.u32`, `.rds`, `embedding.csv`, and container images from the result copy; they
are generated payloads, not manuscript figures. Delete intermediate HPC
payloads only after matching copied checksums and a passing stage audit.
Do not delete original BigANN inputs or unverified results.
