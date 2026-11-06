# HPC resident panel from fastEmbedR main

Package commit: `afeaffc39a607c00db5899c284451c6cdbf741bb`.
Companion scripts from main commit `1b7b924919dce556f0b37286cdd5de52a089b6ed`.
Every planned case is full-data, resident-memory fastEmbedR CPU.
These are within-HPC scaling runs; the active Mac worker uses different
preprocessing and t-SNE settings. See
`benchmarks/shared/cohort-policy-20261106.md` before manuscript comparisons. The plan
contains 11 comparison datasets, PCA, 2D/3D t-SNE, 2D/3D UMAP, Leiden and
Louvain, seeds 4/17/42, and 1/2/4/8/16/32 CPU cores: 1,386 cases. The
source-locked case JSON files are in `cases.jsonl`. Each Slurm array element
runs one scientific fit, with zero GPU exposure and no file-backed input or
algorithm state. The worker and route policy are in the existing
`benchmarks/linux/resident-one-case-20261103` directory.

Dataset audit job 1592295 checked all 11 input digests on a compute node and
completed. CPU pilot 1592789 on the new image completed. An oversized
231-task array 1592791 was cancelled while pending, before any calculation,
because the account would not admit a second array. Quota-friendly waves
1592816, 1592944, 1592817 and 1592945 cover all datasets and five 2D methods at seed 4 on one, two, four and eight cores. They depend on the successful CPU pilot and are throttled to
one running element per array. The full 16- and 32-core seed-4 waves are staged but have not been accepted
by the scheduler: an initial 16-core submit hit
`AssocMaxSubmitJobLimit`. Smaller, 11-case UMAP waves 1593970 and 1593971
were accepted for 16 and 32 cores.
Additional seeds and 3D cases are also staged; submit further small waves
only as quota frees.

On 2026-11-06, Slurm confirmed all 11 UMAP cases in each of the 16-core
and 32-core arrays 1593970 and 1593971 completed with exit `0:0`.
After the queue freed capacity, arrays 1604000 (16 cores) and 1604001
(32 cores) were accepted with `--array=0-3,5-8,10-13%1`. Each contains
12 source-locked, resident-only seed-4 cases: Leiden, Louvain, PCA and
2D t-SNE for COIL20, Fashion-MNIST and flow18. The UMAP positions were
excluded to avoid repeating the completed arrays. Slurm showed element
zero running on Ada with 16 and 32 CPUs respectively; remaining elements
were pending under the array task limit. No scientific outcome is claimed
until each case result and provenance are audited. The other 16/32-core
non-UMAP cases remain staged for later quota-friendly submissions.
The separate two-L40S qualification pilot 1592858 must pass before any CUDA
campaign. Deep1B remains a separate stress study. Comparators, landmarks,
file-backed work and final manuscript analysis are outside these arrays.

`audit_inputs.sbatch` performs checksums inside a compute allocation. Large
SIF checksums also run only inside compute allocations. Never run
file-backed or SSD-streaming scientific work on the HPC.
