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
(22 tests passed on 2026-11-07), `Rscript -e 'parse("matched_worker_scaling.R")'`,
and `bash -n` for the staging and audit scripts.

The two resident flow18 PCA pilot tasks 1606370_16 and 1606371_16 completed
in 7 and 8 seconds. Compute audit 1606374 passed source, case, input,
scheduler, output and memory checks; see [evidence/pca-shape-pilot-audit.json](evidence/pca-shape-pilot-audit.json).
Both report 11 native workers; the observed BLAS settings were 16 and 32.
Fit stages took 0.335 and 0.344 seconds, with job-cgroup peak RAM of 1.17
and 1.21 GB. This qualifies only these two v2 pilots, not the full 462-case
v2 cohort or a 16/32-worker native PCA speedup.

The seven COIL20 resident methods were queued as separate 1/2/4/8/16/32-core
arrays 1606375–1606380 with ten-minute per-case limits and 4 GiB allocations.
All 42 tasks completed. First compute audit 1606417 rejected 36 because Slurm
assigned each array task a distinct numeric `SLURM_JOB_ID`; its failed report
is preserved at [evidence/coil20-wave-audit-v2-failed.json](evidence/coil20-wave-audit-v2-failed.json).
Versioned auditor v3 checks `JobIDRaw` for each exact array index. It reran
read-only on compute job 1606418, with **42/42 audited** and no repeated
scientific calculations. Its report is
[evidence/coil20-wave-audit-v3.json](evidence/coil20-wave-audit-v3.json).
It checks the complete plan identity, exact per-core case roster and Slurm
array indices, backend, source, input, output, memory, timings and scheduler
outcome. These 42 are accepted development cases for package commit `535d071`;
the remaining v2 datasets have not completed.

The source-locked Fashion-MNIST resident wave was queued as six 1–32-core
arrays 1606419–1606424, with seven methods per core, one running task per
array and a one-hour per-case limit. Compute audit 1606449 depends on all six
array terminal states. All 42 passed; see
[evidence/fashion-wave-audit-v3.json](evidence/fashion-wave-audit-v3.json).

The MetRef resident wave used arrays 1606460–1606465 and compute audit
1606502. All 42 cases passed the source, scheduler and result checks; see
[evidence/metref-wave-audit-v3.json](evidence/metref-wave-audit-v3.json).
The USPS resident wave is queued as arrays 1606504–1606509, with compute
audit 1606543. All 42 USPS cases passed; see
[evidence/usps-wave-audit-v3.json](evidence/usps-wave-audit-v3.json).
The MNIST resident wave used arrays 1606549–1606554 and compute audit
1606579. All 42 cases passed; see
[evidence/mnist-wave-audit-v3.json](evidence/mnist-wave-audit-v3.json).

The Tabula Muris seven-method CPU4 pilot used array 1606601 and compute audit
1606606. All seven cases passed; see
[evidence/tabula-cpu4-pilot-audit.json](evidence/tabula-cpu4-pilot-audit.json).

The v2 worker converts `float32` source input to double, while the Mac worker
uses the source `float32` object. This changes memory use and may change fit
timings or quality. Preserve every v2 result as diagnostic evidence. A new
source-locked v3 cohort preserves `float32` and must be used for matched
Mac/HPC comparisons after its independent audit.

The larger mass41 dataset is undergoing a seven-method CPU4 pilot, array
1606597, before the other core counts are submitted. Compute audit 1606599
depends on that array. No mass41 v2 case is accepted yet.
