# Current-candidate Chiamaka CUDA regression check

Scope: one RTX 5060 Ti on Chiamaka, with no UCT HPC job. Rebuild the isolated
fastEmbedR candidate CPU/CUDA package in a new temporary R library using the
existing 29 October source-locked Singularity image. Source archive SHA256:
`de3bd85bc08744381e3fc5a2bc63415d61ce937dd3a6934c4288bfce33d1b643`.
The source includes CUDA graph options, streamed landmark PCA projection,
and parallel CPU clustering restarts. The CUDA check targets regressions
after the latter edits; it does not qualify multi-GPU execution.

Admission: query the device UUID, compute contexts, and image/source hashes.
Only start while no unrelated compute context is present. Compile with
`FASTEMBEDR_USE_CUDA=1` and require the compiled CUDA backend. Run the focused
graph-option and graph-clustering test files against that exact installed
package, with a 90-second timeout per file. On first failure, stop the bundle;
do not start the next GPU case. After each case, query owned process exit and
GPU contexts with finite waits. Preserve logs and any failure evidence. Do
not reset the GPU, restart the host, or alter deployed images or active jobs.

Results, 2 November 2026, UTC: the CUDA build completed in an isolated R
library, with `build mode: cuda`, `CUDA compiled: 1`, and architecture 120.
The installed shared library SHA256 was
`668e14b5863839046b325df6ccb0ce49da71431d5ffb6fee70df9af65f9419ac`.
The image SHA256 was
`3e81f859f48824825ed11928275954a062e6fd324e313bea515d43e1519db402`.
The device was RTX 5060 Ti,
`GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5`.

The `graph-options` test ran from 20:12:04 to 20:12:07 UTC and passed.
The `graph-clustering` test ran from 20:12:23 to 20:12:26 UTC and passed.
Both used the exact isolated installation, each with a 90-second limit.
The GPU compute-app query was empty before the first case, between cases,
and after the second case. The final process check found no candidate-owned
Rscript or container process. The small build and test logs are preserved
under `evidence/`; `evidence/SHA256SUMS` records their identities.

The source archive also contains the corrected README with GitHub reference
links, and excludes `docs/` as specified in `.Rbuildignore`. Thus the
reported relative `docs/*.md` URI warning applies to an older source
archive, not this candidate.
