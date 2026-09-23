# KODAMA JMLR MLOSS confirmatory benchmark

This directory implements the confirmatory and supporting experiments requested
for the KODAMA manuscript. It is intentionally separate from exploratory
benchmarks. No script submits a job automatically.

## Scientific safeguards

1. `preflight_release.R` requires an immutable release lock containing matching
   release tags, clean commits, source archive SHA-256 values, and the container
   SHA-256. A code change requires a new release candidate and a new result tree.
2. The dataset is the inferential unit. The analysis first takes the median over
   seeds within each dataset and only then performs paired inference.
3. Labels are used only for post-hoc metrics. They are never passed to KODAMA,
   landmark selection, initialization, or graph construction.
4. Missing capabilities fail explicitly. The current KODAMA R API must expose
   `folds` in `KODAMA.matrix()` before the frozen five-fold confirmatory run, an
   `ablation` list for the evolution ablation, `landmark.selection` for the
   exact-quota versus uniform comparison, and `search.mode` for exact-search
   backend parity. The scripts never replace these controls with undocumented
   approximations.

## Frozen configuration

- `M = 100`, `Tcycle = 100`, `folds = 5`
- `splitting = 100` for `n < 40000`, otherwise `300`
- `knn.k = 30`, `ncomp = 50`
- UMAP `k = 30`, fuzzy graph; openTSNE perplexity `30`
- seeds `4, 17, 42`; confirmatory backend CUDA
- classifiers KNN and PLS-LDA

The bundled registry lists the eleven currently curated nonspatial datasets.
The confirmatory analysis warns until at least four additional independent
datasets are registered, because the requested target is at least 15 datasets.

## Prepare the immutable release

Copy `release_lock.template.csv` to a permanent benchmark input directory,
fill every field, and create clean source archives from tagged commits. Then run:

```bash
apptainer exec --nv fastembedr_cuda.sif Rscript \
  kodama_mloss_confirmatory/preflight_release.R \
  --release-lock=/scratch/firenze/NN/fastEmbedR-input/kodama-rc1/release_lock.csv \
  --data-root=/scratch/firenze/NN/Data \
  --image=/scratch/firenze/NN/singularity/fastembedr_cuda.sif \
  --out-dir=/scratch/firenze/NN/fastEmbedR-results/kodama-rc1/preflight
```

Do not proceed unless `preflight_status.csv` reports `pass`.

## Generate Slurm jobs

```bash
Rscript kodama_mloss_confirmatory/generate_slurm_jobs.R \
  --suite-dir=/scratch/firenze/NN/kodama_mloss_confirmatory \
  --data-root=/scratch/firenze/NN/Data \
  --result-root=/scratch/firenze/NN/fastEmbedR-results/kodama-rc1 \
  --layout-root=/scratch/firenze/NN/fastEmbedR-rlayout/kodama-rc1 \
  --input-root=/scratch/firenze/NN/fastEmbedR-input/kodama-rc1 \
  --image=/scratch/firenze/NN/singularity/fastembedr_cuda.sif \
  --release-lock=/scratch/firenze/NN/fastEmbedR-input/kodama-rc1/release_lock.csv \
  --out-dir=/scratch/firenze/NN/kodama_mloss_jobs_rc1
```

Inspect the generated commands and submit selected files yourself, for example:

```bash
for f in /scratch/firenze/NN/kodama_mloss_jobs_rc1/confirmatory/*.sh; do
  sbatch "$f"
done
```

## Outputs

- one CSV and compact RDS per dataset/backend/seed;
- layouts outside result tables under `fastEmbedR-rlayout`;
- release and hardware manifest copied into every run directory;
- stage timings plus `/usr/bin/time -v` host-memory logs and CUDA memory traces;
- dataset-median contrast table, 95% dataset-bootstrap confidence intervals,
  exact paired Wilcoxon tests when `coin` is installed, two-sided sign tests,
  Holm-adjusted p values, and forest plots.

`aggregate_confirmatory.R` excludes failed or unmatched rows. FlowRepository or
ImageNet, for example, cannot contribute to a paired claim unless both members
of the contrast completed successfully.

