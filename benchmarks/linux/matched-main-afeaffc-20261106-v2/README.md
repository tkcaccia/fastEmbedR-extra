# Matched resident CPU cohort with job-scoped peak RAM

This is a **new benchmark-script version**, separate from the active
`matched_afeaffc_20261106` source-locked runs. Its Mac-matched scientific
settings and package image are
the same as v1; its result root is
`/scratch/firenze/NN/benchmarks/matched_afeaffc_20261106_v2`.

The v1 runner records stage times and quality but no credible peak RAM.
Slurm `sacct` reported only 2–5 MB `MaxRSS` for completed R cases, so that
field must not be used as the R workload's memory measurement. V1 results
remain development timing and quality evidence, not a complete manuscript
memory cohort.

The v2 runner reads Linux cgroup v2 `memory.peak` immediately before and
after the R child. It accepts the counter only when `/proc/self/cgroup`
places the process under the current `SLURM_JOB_ID` and `step_batch`.
It also records the child's `ru_maxrss` as a secondary process measure.
`memory.json` identifies the counter path, baseline, peak and scope.
If job-scoped peak RAM cannot be verified, the case is marked
`memory_unverified` and returns a nonzero status; it cannot silently become
a complete benchmark result.

Two allocation-only compute-node checks supported this design: job
`1601574` found the per-task cgroup counter on Ada, and job `1601638`
found the same counter inside the release Singularity image. Both reported
`memory.max=max` at the task level, so the runner validates ownership by
job ID and step path instead of requiring a numeric task-level limit.
The v2 COIL20 four-core UMAP pilot `1601661` completed on Ada with exit
`0:0` in four seconds. Its job-scoped `memory.peak` was 1,199,276,032
bytes (1.20 GB), versus 1,045,585,920 bytes (1.05 GB) for the R child.
The baseline before R was 57,180,160 bytes. Slurm's batch `MaxRSS`
was only 23,752 KB for the same job, confirming that `sacct MaxRSS` is
not a suitable substitute here. The pilot recorded CPU backend,
rank-30 preprocessing, trustworthiness 0.9735, label accuracy 0.8917,
completed provenance and a nonempty output RDS. These values are a
single development case, not manuscript performance estimates.

The pilot supports the cgroup counter's plausibility for this four-core
case. Qualify larger multi-CPU cases and audit their memory records before
using a v2 wave in the manuscript.

The four-core USPS Leiden case `1601674` also completed with job-scoped
peak RAM 686,223,360 bytes and child-process peak 529,379,328 bytes.
Its 11,000-row result had 19 communities, modularity 0.8663 and ARI
0.4565. The earlier v1 case with the same input and seed reported 19
communities, modularity 0.8650 and ARI 0.4771. The v2 worker changed only
by explicitly passing `massive = "off"` to embedding calls; the clustering
call is unchanged. This quality difference needs a controlled graph-versus-fit
repeatability audit before either result supports a reproducibility claim.
`audit_cluster_repeatability.R` is a bounded, resident-only diagnostic for
that audit. It uses its own versioned HPC path,
`matched_afeaffc_20261106_repeatability_v1`.

Diagnostic job `1601713` completed on Ada with exit `0:0` using the
checksum-verified resident USPS input. Two four-core graph builds differed;
two one-core graph builds were identical. Repeating Leiden twice on the
same four-core graph gave identical memberships. Leiden on the two different
four-core graphs differed; Leiden on the two one-core graphs matched.
Thus the observed variation entered during four-core graph construction in
this case. The current CPU KNN policy selects HNSW above 5,000 rows,
which is a plausible mechanism, but the diagnostic did not isolate FAISS
internals. For paired clustering quality and fit-scaling comparisons, use
a versioned benchmark with a deterministic graph construction step and
record the graph identity. Keep the current four-core graph-build cases as
end-to-end variability evidence.

The worker and planner reject file-backed input, nonresident algorithm
state, spill and GPU exposure. The package image remains release commit
`afeaffc39a607c00db5899c284451c6cdbf741bb`. Never hash its 9 GB
image on the HPC head node; its digest was verified on a compute node.
Do not mix v1 and v2 cases into one manuscript cohort.
