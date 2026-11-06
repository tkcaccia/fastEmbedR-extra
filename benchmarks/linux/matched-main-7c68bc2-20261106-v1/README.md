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
both match the local plan. Submit the remaining v2 cases in bounded waves
after pilot review and when scheduler capacity permits. Do not submit v1 or
mix either plan with the earlier `afeaffc` cohort.

At 18:06 UTC on 2026-11-06, bounded v2 qualification began before the
larger waves. CPU8 COIL20 PCA job `1605210_2` completed `0:0` and passed the
read-only scaling audit: backend `cpu_rsvd`, eight requested and eight
reported effective workers, fit time 0.645 s, and Slurm job-cgroup peak RAM
1,363,234,816 bytes. This one small fit is not a speedup estimate. The six
other COIL20 CPU8 method/dimension pilots ran as array `1605219` with one
active task and a 20-minute limit per case. Leiden, Louvain, and 2D/3D UMAP
completed. Both t-SNE cases failed the worker-count guard before metrics were
written; their logs and failed provenance remain intact. The read-only audit
found five accepted pilots (including PCA), two failed cases, and 378
unsubmitted cases. These are diagnostic results, not a scaling comparison.
The full 385-case scaling waves remain unsubmitted.
The separate auditor is
`/scratch/firenze/NN/benchmarks/audit_scaling_7c68bc2_20261106_v1/audit_scaling.py`
(SHA-256 `50ed5f1e585156ef0d9b2fd8b022db60d28da9b7ef7eff4c78c314182df37974`).
It verifies the staged plan files and each result's effective CPU count,
source, input, quality, memory, and scheduler outcome using small manifests.
The initial auditor labels the failed t-SNE cases `incomplete_result` because
their metrics files are absent. A versioned v2 auditor preserves the explicit
`failed_case` classification from terminal provenance and has a focused test.
Its source SHA-256 is
`78df0f012f310396a5ce662e4e6589c2e92139ff5d5980c80a88cb937fee0a81`;
the separate HPC copy is at
`/scratch/firenze/NN/benchmarks/audit_scaling_7c68bc2_20261106_v2`.
The partial v2 review reports five audited, two failed, and 378 missing.
No failed case is retried in place.

The t-SNE source applies an adaptive cap to every request: at COIL20's 1,440
rows, `n.cores = 8` is reduced to two native workers. This explains why the
worker's request-versus-effective check stopped both cases. An isolated
package candidate applies that size-based cap only to automatic selection and
honors an explicit worker request. The change passed source-style checks and
has a focused native-result metadata test. A CPU-only compute-node build and
baseline-versus-candidate check was submitted as job `1605266`; its terminal
result must be reviewed before the change is published or any eight-core
t-SNE scaling case is submitted under a new source version.
