# Matched resident CPU scaling v2 candidate

This is a separate benchmark-code cohort for package commit
`535d071849945db3fa550d3c50f80633b91748cc`. Do not alter or reuse the
running v1 cohort; never combine v1 and v2 rows into one manuscript cohort.
The v2 plan was staged at
`/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v2` by
compute job 1606369, with its 462-case plan and worker/runner hashes checked.

The v1 flow18 PCA tasks at 16 and 32 allocated cores failed the worker-count
check. Flow18 has 11 columns. The package's native PCA projection calls
`resolve_projection_threads(requested, ncol)`, so it reports 11 native workers
for both cases. This is a shape limit, not evidence that the requested 16 or 32
workers were used. The BLAS thread request and observed BLAS setting are
recorded separately because other PCA phases may use a different thread count.

The v2 worker accepts the exact native limit `min(requested_cores, ncol)` for
PCA and still rejects any other unexpected worker count. The v2 auditor checks
the limit and its explicit metadata. Non-PCA routes still require the requested
number of effective workers. The two v1 failures and their logs remain evidence.

CPU-only source checks: `python3 -m unittest discover -s . -p 'test_*.py' -q`
(19 tests passed on 2026-11-07), `Rscript -e 'parse("matched_worker_scaling.R")'`,
and `bash -n` for the staging and audit scripts.

The two resident flow18 PCA pilot tasks 1606370_16 and 1606371_16 completed
in 7 and 8 seconds. Compute audit 1606374 passed source, case, input,
scheduler, output and memory checks; see [evidence/pca-shape-pilot-audit.json](evidence/pca-shape-pilot-audit.json).
Both report 11 native workers; the observed BLAS settings were 16 and 32.
Fit stages took 0.335 and 0.344 seconds, with job-cgroup peak RAM of 1.17
and 1.21 GB. This qualifies only these two v2 pilots, not the full 462-case
v2 cohort or a 16/32-worker native PCA speedup.
