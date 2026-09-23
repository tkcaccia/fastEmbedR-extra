# KODAMA JMLR CPU4 ablation benchmark

This directory implements the frozen CPU-only protocol in
`docs/JMLR_CPU4_ABLATION_HPC_PROTOCOL.md`. It never submits a job during setup.

The current public `kodamaR` wrapper must expose both `folds` and a named
`evolution.policy` (or `evolution_policy`) argument before the benchmark is
valid. `preflight.R` deliberately fails when either is absent. Do not replace
the named ablations with benchmark-side approximations.

The generated dependency order is:

1. release/API/data preflight;
2. one reusable CPU4 `KODAMA.graph()` per dataset, representation, and seed;
3. isolated cell array for ablations, predictor sensitivity, and classic
   visualizations.

Every process uses one Slurm task with four CPUs. OpenMP receives four workers;
BLAS libraries receive one worker to prevent nested oversubscription.

Generate the scripts on the HPC with:

```bash
cd /scratch/firenze/NN
Rscript kodama_cpu4_ablation_hpc/generate_slurm.R \
  --root=/scratch/firenze/NN \
  --code-dir=/scratch/firenze/NN/kodama_cpu4_ablation_hpc \
  --release=8d5339a \
  --image=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
```

Inspect `kodama_cpu4_ablation_8d5339a/cells.csv`, then explicitly submit:

```bash
bash /scratch/firenze/NN/kodama_cpu4_ablation_8d5339a/submit_all.sh
```

No labels are passed to KODAMA. They are loaded only after fitting for external
diagnostics. Failed cells retain a status row and nonzero `exit_status.txt`.
