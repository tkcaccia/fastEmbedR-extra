# File-backed multi-CPU clustering scratch reuse candidate

Isolated fastEmbedR candidate commits: `34ad265` and `7852822` in
`in-progress/fastembedr-8gpu-resident-cluster-20261106`. This commit is
local only; the package main on GitHub remains at `3294441` until the
candidate is qualified.

The C++ Louvain proposal and Leiden refinement paths previously created a
new vector of per-row maps and labels in every bounded parallel batch. The
candidate retains that vector across bounded batches, graph segments and
passes, and clears its contents before reuse. The 65,536-edge batch cap
and sequential move application order are unchanged, so the bounded
scratch limit and intended
label order are preserved. It does not change the single-CPU path.

`src/massive_matrix.cpp` passed Linux C++17 syntax checking with the local
Rcpp and R headers, and `git diff --check` passed. This is **not** a
performance or correctness qualification. After the active source-locked
Mac panel finishes, build this candidate under Stefano and compare one,
two, four, eight and sixteen CPU workers against the same file-backed graph
with identical input identity, seed, partition labels, modularity, peak RAM,
and cleanup. Compare it to the recorded baseline in
`benchmarks/macos/multicpu-scaling-20261105/README.md`. Keep every failed
or slower result as evidence; do not promote this candidate merely because
it compiles.
