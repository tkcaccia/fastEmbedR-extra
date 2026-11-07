# Matched resident CPU scaling v2 candidate

This is a separate, **unstaged** benchmark-code candidate for package commit
`535d071849945db3fa550d3c50f80633b91748cc`. Do not alter or reuse the
running v1 cohort. Generate a new source-locked plan and result directory before
running v2; never combine v1 and v2 rows into one manuscript cohort.

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
(17 tests passed on 2026-11-07), and `Rscript -e 'parse("matched_worker_scaling.R")'`.
These checks do not qualify the v2 HPC scientific output. A new compute-node
pilot and terminal audit are needed before reporting any v2 results.
