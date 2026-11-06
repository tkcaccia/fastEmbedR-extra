# Matched resident CPU cohort with job-scoped peak RAM

This is a **new benchmark-script version**, separate from the active
`matched_afeaffc_20261106` source-locked runs. No scientific v2 case has
been submitted. Its Mac-matched scientific settings and package image are
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
These checks establish counter visibility, not yet whether its peak captures
the full multi-CPU R workload. A small v2 scientific pilot and memory
plausibility audit are required before any v2 wave is submitted.

The worker and planner reject file-backed input, nonresident algorithm
state, spill and GPU exposure. The package image remains release commit
`afeaffc39a607c00db5899c284451c6cdbf741bb`. Never hash its 9 GB
image on the HPC head node; its digest was verified on a compute node.
Do not mix v1 and v2 cases into one manuscript cohort.
