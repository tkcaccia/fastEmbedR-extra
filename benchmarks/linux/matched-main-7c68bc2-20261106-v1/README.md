# Source-locked resident CPU benchmark candidate: 7c68bc2

This is a new cohort for package commit
`7c68bc2a48ff3f98d07f216db9601047951827fd` and the immutable HPC image
`/scratch/firenze/NN/singularity/release_7c68bc2_20261106/fastembedr_7c68bc2_20261106.sif`.
Its result root is `/scratch/firenze/NN/benchmarks/matched_7c68bc2_20261106_v1`.
It is separate from the running `afeaffc` Mac and HPC cohorts. No case in
this directory is a final manuscript result until device, input, quality,
memory, and scheduler audits pass.

The planner requires exact input rows, columns, and SHA-256, along with the
resident storage and no-spill declaration. It rejects unreviewed controls,
nonresident routes, and landmark routes that the current worker cannot run.
The case runner checks the input file's SHA-256 in its **Slurm compute
allocation**, before the R worker loads data. It reads in bounded 8 MiB
chunks, records the actual digest, file size, and verification time, and
preserves a mismatch as a failed case. Do not run this checksum on the HPC
head node. It does not hash the large Singularity image on the head node.

Each allocation makes one scientific fit. The worker checks input shape,
resident data, output shape, finite values, requested CPU backend, and the
reported effective workers where available. It records stage timings and
quality. Job-scoped cgroup `memory.peak` is required for a completed case;
an unverified memory counter yields a nonzero result. The package's existing
four-core HNSW graph construction showed repeatability variation on USPS;
clustering rows in this cohort need graph-identity audit before paired
quality claims.

`case.json` and `pilot.sbatch` stage a single COIL20 UMAP compute-node pilot.
The 77 planned full-data CPU cases pass the pure route policy. The wave
scripts and case lists are staged only; do not submit waves until the pilot
and its input identity, source identity, backend, memory, quality, and cleanup
are audited. The active `afeaffc` scripts and jobs are unchanged.

`audit_results.py` is a read-only terminal review. Supply a saved `sacct`
pipe-delimited table with `JobIDRaw,JobID,State,ExitCode`; it checks the
77 result manifests, source hashes, actual input checksums, method and backend,
quality ranges, cgroup memory, output presence, and scheduler outcome. It
returns nonzero while any case is missing or fails. Its review reads only
small manifests and file metadata, so it can run on the head node without
reading dataset contents or the Singularity image.

`audit_results_v2.py` is a versioned, stricter terminal review staged while
the v1 scientific jobs run. It additionally requires the recorded package
version, seed, storage mode, fit scope, backend, preprocessing rank, and
result filename to match each case manifest. The active Slurm scripts and
workers were not changed. `test_audit_results_v2.py` passes a valid fixture
and rejects each altered route field. Run v2 on the completed cohort before
using its results in manuscript comparisons; a passing audit still does not
replace direct output-quality and graph-identity review.

The v2 script (SHA-256
`6e0c0a061ee9cdc63313578c76ee8fbc3c7d821f299c052bdc2f8c1774fd51b1`)
was copied and checksum-verified in a **separate** HPC directory,
`/scratch/firenze/NN/benchmarks/audit_7c68bc2_v2_20261106`. Its accounting
table includes the five pilot jobs as well as all three arrays. A partial
review on 2026-11-06 found 66 audited results, three running, and eight not
yet written; it found no audit failures. The cohort is not terminal and this
is not a final acceptance result. Only small manifests, scheduler records,
and the 7 KB auditor script were read on the head node.

`plan_scaling.py` stages the missing matched CPU counts (1, 2, 8, 16, 32)
from the 77 reviewed four-core cases. Its three tests require all eleven
datasets and seven method/dimension combinations, reject any file-backed,
streaming, spill, or altered fit scope, and verify one scientific fit per
array element. The generated plan contains 385 cases with unchanged input
digests and the same `7c68bc2` image; all five Slurm scripts pass `bash -n`.
The initial plan at
`/scratch/firenze/NN/benchmarks/matched_scaling_7c68bc2_20261106_v1`
was not submitted. An audit found that its reused worker did not verify
effective PCA and t-SNE CPU counts. The corrected v2 plan bundles its own
unchanged resident runner and route policy, plus
`matched_worker_scaling.R`, which checks and records effective CPU counts
for all five methods. Its R source parses, the three planner tests pass,
and the five Slurm scripts pass `bash -n`.

The corrected plan is staged at
`/scratch/firenze/NN/benchmarks/matched_scaling_7c68bc2_20261106_v2`.
Its remote 385-case manifest SHA-256 is
`d840d1351ff9cb8b221e3f673d20a74c5e2997432bb40e27011d1ad3cab12356`,
and the staged R worker SHA-256 is
`9b7c51b3d34359a30b31ce208d3bf9503b755ea10d82aa2791b5249b635d3e31`;
both match the local plan. No scaling job has been submitted. Submit v2 in
bounded waves after the running four-core cohort reaches a terminal audited
state and scheduler capacity permits. Do not submit v1 or mix either plan
with the earlier `afeaffc` cohort.
