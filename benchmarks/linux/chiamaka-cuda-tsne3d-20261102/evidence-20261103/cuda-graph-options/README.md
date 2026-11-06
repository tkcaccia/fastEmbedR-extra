# CUDA Louvain and Leiden graph-options regression

The shared GPU graph-options path was rebuilt with strict CUDA in the
existing Chiamaka Singularity image on 3 November 2026. Source archive
SHA256:
`11cf564c8932821eb38c3bbc973453c2d8c8bb3476a93b836f027cac3978102a`.
Installed library SHA256:
`9fe515821ff9b51e7ecfdb4a9afd68556f0e87cdaaa2575b16a58c86fa7c59d3`.

On the idle RTX 5060 Ti, native CUDA Leiden and Louvain passed combined
four-partition consensus, projection weighting, and small-group handling
on an 18-vertex graph. Sparse consensus weights matched a manual
coassignment calculation. A mocked CPU clustering route would have stopped
the test. Each final result reported two communities and 46 weighted edges.
The bounded test exited in under three seconds and left no GPU context.

The initial test script stopped before calculation because it expected an
argument that the runner supplies as an environment variable. The corrected
script passed; `validate.log` contains the final output. `build.log`
records the strict CUDA installation. This small graph check does not
establish large-graph performance or multi-GPU option behavior.
