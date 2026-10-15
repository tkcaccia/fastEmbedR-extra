# Independent 20M two-GPU PCA retry

The 2026-10-13 Deep1B campaign has one Slurm failure: job 1447652.
Its PCA stage completed in 27.577 seconds and wrote 20M-row metrics,
but the process-PID memory monitor observed only one of two GPUs.
The original nine running jobs must not be stopped or have their
source-locked scripts changed to investigate this failure.

This retry uses the same input rows, PCA call, image, and existing
`run_full_graph.R`. New scripts sample **device-wide** memory on the two
GPU indices reported by `SLURM_JOB_GPUS`, before and during the fit.
The audit passes only when both devices increase above baseline, the
PCA manifest reports distinct completed device shards, 20M score rows
are present and finite at sampled positions, quality scoring succeeds,
and the all-row PCA figure exists. An allocation of two GPUs alone is
not counted as two-GPU execution. The output records per-device peak
and baseline-adjusted VRAM, the fit's peak RSS, stage time, and the
PCA quality sample. A failed retry retains its output for diagnosis;
a passed retry removes the large binary score payload after scoring.

Copy only the new scripts from the Mac. Do not use `--delete` or copy
over the active campaign's existing scripts:

```bash
SRC=/Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/massive-data/deep1b
HOST=01481067@hex.uct.ac.za
REMOTE=/scratch/firenze/NN/benchmark_scripts/massive-data/deep1b
rsync -av "$SRC/gpu_memory_allocated.py" \
  "$SRC/verify_retry_pca_2gpu.R" \
  "$SRC/run_retry_pca_2gpu.sh" \
  "$SRC/submit_retry_pca_2gpu.sh" \
  "$HOST:$REMOTE/"
```

Submit on the HPC login node. The quota variable must be the free
personal `/scratch` quota in bytes; `df` alone does not show that quota.
This job has no dependency on the other nine jobs.

```bash
cd /scratch/firenze/NN
export DEEP1B_QUOTA_FREE_BYTES="$(
  myquota | awk '$1 == "/scratch" {
    gsub(/GB/, "", $2); gsub(/GB/, "", $3)
    printf "%.0f", ($2 - $3) * 1000000000
  }'
)"
bash benchmark_scripts/massive-data/deep1b/submit_retry_pca_2gpu.sh
```

After the job, inspect the printed campaign directory's `audit.json`,
`gpu_summary.json`, `gpu_memory.csv`, `pca_per_device.csv`, `stages.csv`,
`time.txt`, `quality.csv`, and PCA PNG. If the second card remains
inactive, report this as a package multi-GPU execution problem rather
than weakening the audit. The 1M KNN recall warnings in the original
campaign are not Slurm job failures; they need a separate, prespecified
tuning and holdout experiment, not an untracked retry.
