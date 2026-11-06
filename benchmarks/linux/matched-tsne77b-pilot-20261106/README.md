# Source-locked COIL20 CPU8 t-SNE pilot

This is a real-data, resident-memory 3D t-SNE pilot for package main commit
`77b852fc496ad4665969c4f6771088f5b98da4fe` and immutable HPC image
SHA-256 `ca7c58b98c180571e3a103258598ad7dbcb4354fb1abde3fc319aab2bc004b6b`.
It is separate from the `7c68bc2` cohort, whose two CPU8 t-SNE pilots failed
because the package used only two workers. The failed artifacts are retained.

The case uses all 1,440 COIL20 rows in RAM. It requires exactly eight
allocated and reported effective CPU workers, 30-dimensional resident CPU
PCA preprocessing, 3D output, finite values and a CPU backend. The runner
checks the raw input SHA-256 in the compute allocation, records stage timing,
embedding quality, source hashes, cgroup peak memory and scheduler identity.
The image is hashed inside the allocation against the digest computed by its
build job. No file-backed or SSD-streaming scientific route is allowed.

This one case is a qualification run. It cannot establish scaling or become
a manuscript comparison until a complete same-source cohort and independent
terminal audit pass.
