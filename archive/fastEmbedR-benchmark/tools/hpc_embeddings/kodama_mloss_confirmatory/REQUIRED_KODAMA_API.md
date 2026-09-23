# Public API required by the frozen benchmark

The current benchmark deliberately stops before expensive computation until the
following controls are public, documented, serialized in `parameters`, and
covered by wrapper tests. This prevents a script from claiming a reviewer
experiment while running different mathematics.

## `KODAMA.matrix()`

```r
KODAMA.matrix(
  ...,
  folds = 5L,
  landmark.selection = c("exact_quota", "uniform"),
  ablation = list(
    prediction_guided = TRUE,
    adaptive_proposal_size = TRUE,
    error_scaled_temperature = TRUE,
    degeneracy_guard = TRUE,
    transition_coarsening = TRUE,
    pls_fragmentation = TRUE
  )
)
```

`folds` must reach the same native cross-validation code used by proposal
evaluation. It must not affect only a diagnostic CV call.

An empty `ablation=list()` means the accepted production implementation. Each
named Boolean disables exactly one contribution while all other code and random
streams remain unchanged. Unsupported names must error.

`landmark.selection="uniform"` means a uniform sample without replacement.
`"exact_quota"` means the accepted quota-preserving selection. Labels from the
benchmark dataset must not participate in either selection.

## `KODAMA.graph()`

```r
KODAMA.graph(..., search.mode = c("production", "exact"))
```

`exact` is for moderate-size CPU/CUDA/Metal parity testing. `production` is the
normal approximate route. The returned object must record the requested and
actual route and must never silently fall back.

## Additional result fields

For complete reviewer tables, `KODAMA.matrix()` should return:

- stage timings: landmark selection, CV evolution, projection, agreement
  correction, graph work, and total;
- selected landmark row indices;
- one projection distance per nonlandmark row;
- best and per-run CV accuracy;
- active-class trajectory or at least final active classes;
- a numerical-failure/collapse status;
- graph build count and backend actually used.

The C++, R, and Python wrappers must expose identical names and reject invalid
values consistently.

