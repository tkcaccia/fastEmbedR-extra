# Per-dataset Slurm submitters

These wrappers submit the already-generated profile launchers independently.
Each dataset has two scripts:

- `run_<dataset>_all_methods.sh`: all embedding and reference methods for
  CPU-1, CPU-4, and CUDA.
- `run_<dataset>_KODAMA.sh`: the KODAMA-only workflows for CPU-1, CPU-4, and
  CUDA.

The three profiles are separate Slurm jobs because CPU and GPU resource
requests cannot safely be combined in one job. The underlying launchers are
stored in `jobs_by_dataset/` and `kodama_jobs_by_dataset/`.

On the HPC, after copying the complete benchmark support tree to
`/scratch/firenze/NN`, run for example:

```bash
bash dataset_submitters/run_MNIST_all_methods.sh
bash dataset_submitters/run_MNIST_KODAMA.sh
```

Use `DRY_RUN=true` to inspect the three `sbatch` commands without submitting:

```bash
DRY_RUN=true bash dataset_submitters/run_MNIST_all_methods.sh
```

To regenerate the wrappers:

```bash
Rscript tools/hpc_embeddings/generate_dataset_submitters.R \
  tools/hpc_embeddings/dataset_submitters
```
