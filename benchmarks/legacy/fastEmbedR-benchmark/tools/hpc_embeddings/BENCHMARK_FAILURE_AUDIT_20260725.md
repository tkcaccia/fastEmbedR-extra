# Benchmark failure audit: 2026-07-25

## Conclusions

The reviewed failures did not have one common algorithmic cause.

1. Several KODAMA jobs were cancelled together at `2026-07-25 09:37:42`.
   These are interrupted runs, not package failures.
2. CUDA jobs assigned to `srvrocgpu016` reported
   `uncorrectable ECC error encountered`. This is a GPU/node health failure.
3. ImageNet and FlowRepository CPU workers exited with status 137 at about
   7.4 GB RSS. Their launchers had no `#SBATCH --mem` directive, so Slurm
   killed them at the job cgroup limit even though the cluster had free RAM.
4. KODAMA caches were keyed by the unchanged R package version (`0.1.0`) and
   could therefore reuse results produced by an older core build.

Timezone, Fontconfig, and `git rev-parse` warnings were not responsible for
method failures.

## Corrections

- Every launcher now requests memory explicitly.
  - standard and landmark: 32 GB normally, 128 GB for FlowRepository, and
    256 GB for ImageNet on CPU;
  - KODAMA: 64 GB normally, 192 GB for FlowRepository, and 256 GB for
    ImageNet on CPU;
  - CUDA jobs request 64-128 GB host RAM according to dataset.
- CUDA jobs run an `nvidia-smi` ECC check and a small CuPy allocation/kernel
  test before the benchmark. A failed node is excluded from the requeued job
  when Slurm permits the update.
- KODAMA cache names include a tag derived from the actual Singularity image
  identity, preventing old results from being reused after an image rebuild.
- Exit 137 is reported explicitly as a likely Slurm cgroup memory kill.
- OOM, timeout, and other failed worker rows are no longer treated as reusable
  cached results.
- A CUDA health failure stops subsequent methods on that device instead of
  repeating the same deterministic failure for every seed.

## Canonical files

The corrected files are under `tools/hpc_embeddings`:

- `run_reviewer_dataset_job.sh`
- `benchmark_reviewer_validation.R`
- `jobs_by_dataset/`
- `landmark_jobs_by_dataset/`
- `kodama_jobs_by_dataset/`

After the HPC mirror is mounted, synchronize them with:

```bash
bash tools/hpc_embeddings/sync_reviewer_jobs_to_hpc_mirror.sh
```

