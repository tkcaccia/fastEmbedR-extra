# HPC resident panel from fastEmbedR main

Package commit: `afeaffc39a607c00db5899c284451c6cdbf741bb`.
Companion scripts from main commit `1b7b924919dce556f0b37286cdd5de52a089b6ed`.
Every planned case is full-data, resident-memory fastEmbedR CPU. The plan
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
one running element per array. The remaining cores, seeds and 3D cases are
staged but have not been submitted; submit further small waves as quota frees.
The separate two-L40S qualification pilot 1592858 must pass before any CUDA
campaign. Deep1B remains a separate stress study. Comparators, landmarks,
file-backed work and final manuscript analysis are outside these arrays.

`audit_inputs.sbatch` performs checksums inside a compute allocation. Large
SIF checksums also run only inside compute allocations. Never run
file-backed or SSD-streaming scientific work on the HPC.
