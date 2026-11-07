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
The remaining COIL20 CPU1/2/8/16/32 waves 1606627–1606631 completed. Their
first dependent audit 1606656 exited before reading results because Slurm
parsed the comma-delimited job-ID environment variable as multiple exports.
Its empty logs and scheduler failure are preserved. The versioned audit script
uses colon-delimited IDs. Read-only audit 1606665 passed **42/42** without
repeating any scientific job; see `evidence/coil20-wave-audit-v3.json`.
These cases are source-locked to this v3 worker and are not yet publication
results.

The Fashion-MNIST v3 resident wave is queued as CPU1/2/4/8/16/32 arrays
1606667–1606672 with seven cases per core, a one-hour per-case limit and one
concurrent task per array. Audit 1606680 is dependent on all six terminal
states. It passed **42/42**; see `evidence/fashion-wave-audit-v3.json`.

The MetRef v3 resident wave used arrays 1606716–1606721. Compute audit
1606750 passed **42/42**; see `evidence/metref-wave-audit-v3.json`.

The USPS v3 resident wave used arrays 1606779–1606784 for CPU1/2/4/8/16/32,
with exactly seven cases per core and a 15-minute per-case limit. Compute
audit 1606785 passed **42/42**; see `evidence/usps-wave-audit-v3.json`.

The MNIST v3 resident wave uses arrays 1606828–1606833 for CPU1/2/4/8/16/32,
with exactly seven cases per core and a 20-minute per-case limit. Its dependent
audit 1606834 must pass before treating any case as an audited result.

A Tabula Muris v3 CPU4 seven-method pilot was array 1606868 with a one-hour
per-case limit. Compute audit 1606869 passed **7/7**; see
`evidence/tabula-cpu4-pilot-audit-v3.json`. The remaining CPU1/2/8/16/32
arrays are 1606883–1606887 with a 35-minute per-case limit. Dependent full
wave audit 1606888 will check all 42 cases after those arrays terminate.
