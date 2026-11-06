# Experimental Metal 3D t-SNE bounded graph streaming, 3 November 2026

The isolated candidate at `in-progress/metal-landmark-3d-20261102` now
exposes `graph_access = "auto"`, `"mmap"`, or `"stream"` and
`edge_chunk_capacity` through `massive_tsne_optimize()`. Auto selects
streaming when the affinity graph exceeds one chunk. Streamed mode maps
CSR files read-only on the host and copies at most the requested number
of edges into reusable Metal buffers. It keeps the complete 3D layout,
optimizer state, and FFT workspace resident. This is bounded graph
staging, not a fully out-of-core t-SNE implementation.

The tested Mac installation is under
`/Users/silvanopiazza/Documents/Stefano/metal-tsne-stream-20261103`.
The installed `fastEmbedR.so` SHA256 is
`e09614a71b25c5575d1e5add83275514dbe048ce24305d83376d58ab44f74308`.
Generated compiler objects were removed after installation; the folder
occupies 12 MB. The original Mac benchmark panel was not resumed.

The focused test passed 19 assertions, with no failures, warnings or
skips. It covered forced and automatic streaming, mapped/streamed exact
coordinate equality, invalid edge capacity, and an interrupted streamed
checkpoint/resume. Log: `focused_test.log` (SHA256
`f449fc7d0243995381e6e50e3fd48d6735ad4aa0f79ce283af439d9a3ee0bee7`).

The existing FashionMNIST 70,000-row exact-neighbor graph had 3,362,694
directed edges. Five iterations from the same graph and start gave the
same layout MD5 `a725622dced82e3576c4f4d1e10c45b2` in mapped and
streamed modes, with maximum coordinate difference zero. At 65,536
edges per chunk, the streamed fit took 0.148 s versus 0.070 s mapped
in this one short run. These timings exclude graph construction and do
not qualify large-scale throughput or quality. The script removed its
generated graph and layout files. Log: `fashion70k_compare.log` (SHA256
`e468ada5006a68267be74d5ee934aeebc671ee45c275bffdf3ffa090270506b9`).
Script SHA256:
`edd36619b0b440355dbd744da651d80e8db66b6c1c66a4ea200a93b8d0b364a0`.

Current source SHA256 values: R API
`f37547d57ce07aba9de9a194c1033f0632a3522242acef0ee542c640f03fcbaa`,
Metal implementation
`98c4e2236be924e862375fa9336223262dfe798db5811144fad7510082fbdc83`,
3D Metal kernel header
`18db15d2e159fe5185c8c4cfc0755968f7b70717adc72558ba0ba2fe27e3b188`.
Local `git diff --check` and source style passed. Roxygen generation on
the Linux PC failed because its R 4.5.2 is below the package's R 4.6.0
requirement; the single affected help page was updated manually.

Broader Mac checks passed after correcting the test invocation and one
stale expectation: the installed-package 3D t-SNE test passed 45
assertions, with five CUDA-only skips; `test-metal-stages.R` passed 82;
and `test-massive-metal.R` passed 121. The first combined `regression.log`
is retained because it records the initial test-harness errors and the
stale assertion. Corrected logs are `tsne3d_regression.log` (SHA256
`67ebec1817bd4d447f93d794de814eb6d9b245f6f7d2b62d94e5e4386e4ef3dd`)
and `metal_regression_corrected.log` (SHA256
`aea62c112fe620cbad9838f45a8903e53fc6257f950a23769bc99779f9270b99`).

Large graphs, memory peaks, device buffer limits, real-dataset quality,
and throughput remain unqualified. The 3D FFT near-field algorithm
also needs scaling work before Deep1B 100M. Metal 2D file-backed t-SNE
remains absent.
