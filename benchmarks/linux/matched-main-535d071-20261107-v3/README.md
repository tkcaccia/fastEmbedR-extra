# Matched resident CPU cohort v3

This cohort uses the same package commit, input files, row selection, methods, and
parameters as v2. Its worker preserves the source `float32` input and the
`float32` CPU PCA preprocessing output used by the source-locked Mac panel.
The v1 and v2 HPC CPU cohorts converted the input to double before fitting;
preserve them as diagnostic evidence and do not combine their timings or quality
values with the Mac panel in a manuscript comparison.

The 462-case plan runs seven methods on eleven datasets at 1, 2, 4, 8, 16,
and 32 CPU cores. Each Slurm allocation runs one resident scientific case. The
worker rejects file-backed input and any loss of `float32` precision. The
independent auditor checks precision, source and input identity, backend,
effective core count, quality, job outcome, and cgroup memory evidence.

Start with a seven-method COIL20 four-core pilot. Keep every failed result and
its logs. Only expand the cohort after the pilot audit passes. The full plan
still requires dataset-specific memory and time admission before submission.

The plan-stage compute job 1606617 verified the 462-case source identity.
COIL20 CPU4 pilot 1606618 completed all seven cases; independent audit 1606624
passed seven of seven. Its report is in `evidence/coil20-cpu4-pilot-audit.json`.
The remaining COIL20 CPU1/2/8/16/32 waves are 1606627–1606631, with dependent
42-case audit 1606656. These are source-locked to this v3 worker and are not
yet publication results.
