# New-image L40S pilot and subsequent case gate

This is a development audit, not a manuscript result. Times are UTC.

## New-image pilot 1592858

- Slurm `sacct` reported `COMPLETED`, exit `0:0`, elapsed `00:00:31`,
  on `srvrocgpu013` on 2026-11-06.
- The compute-node runner verified image SHA256
  `6db5eddc7b998a6ef7822930ddeb096f5da324056e9b1cf297246b5069a964df`.
  The image is the read-only `fastembedr_afeaffc_20261106.sif`, built from
  fastEmbedR commit `afeaffc39a607c00db5899c284451c6cdbf741bb`.
- Slurm assigned GPUs `2,3`, mapped inside the allocation to visible `0,1`.
  UUIDs were `GPU-011f3a98-ffee-484d-e975-539ebcdfbdb8` and
  `GPU-a3df5d7b-6494-7a50-6a05-0af05474745a`.
- The 160-row resident landmark UMAP test reported CUDA backend, native CUDA
  exact neighbors, landmark CUDA refinement and both assigned GPU identities.
  The runner recorded `HPC_RESIDENT_UMAP_2GPU_PASS`, one-attempt
  `cleanup_verified`, and `pilot_pass`. Its error file was empty.
- Evidence: `/scratch/firenze/NN/singularity/release_afeaffc_20261106/`
  `pilot-afeaffc-1592858.out` and `pilot-afeaffc-1592858.err`.
  The image digest was calculated on the compute node; do not hash the
  9 GB image on the head node.

This pilot qualifies a small native resident route and lifecycle. It does not
establish COIL20 quality, performance, three-GPU scaling, or a manuscript result.

## COIL20 case 1594628

The pre-submitted, source-locked COIL20 resident UMAP case was held while the
new-image pilot ran. Its manifest requests 1,440 rows, 16,384 columns,
two L40S GPUs, 2D UMAP and seed 4. Its worker explicitly sets
`massive = "off"`; the policy requires resident input and state, disallows
spill, and checks the input digest and exact dimensions on the compute node.
The case launcher has a 180-second application deadline, bounded owned-process
shutdown, assigned-context checks and a scheduler warning margin.

After the pilot audit and confirmation that the result path and allocation
claim were absent, job 1594628 was released on 2026-11-06. At 12:53 UTC it
was still `PENDING (Resources)`. Do not infer a scientific result from the
release. On terminal state, audit Slurm, source/image/input identity, backend
and devices, quality, peak memory and owned-context cleanup before any wider
GPU campaign.

## Distinct Mac-matched candidate

The separate `matched-v2` CUDA case is staged but **not submitted** at
`/scratch/firenze/NN/benchmarks/resident_gpu_matched_afeaffc_v2`.
Its small archive SHA256 is
`4c4fba8c93768936049e04121d427fbfbebcb9605d4a52e27f524745850d1934`,
from fastEmbedR-extra main commit
`828bd4880539f867f52f5c90e30a9a2b0f9cdb4b`. The archive was verified on
HPC and the staged scripts are read-only. This version explicitly sets
`massive = "off"` for resident preprocessing PCA and GPU fits. It uses
rank-30 PCA preprocessing, matching the Mac cohort, and must remain separate
from the raw-input COIL20 diagnostic above. Submit only after 1594628 has a
clean terminal audit and the matched case has its own final admission review.
