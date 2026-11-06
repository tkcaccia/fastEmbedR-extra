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
