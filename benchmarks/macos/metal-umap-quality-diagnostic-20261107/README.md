# Fixed-graph Fashion Metal UMAP optimizer diagnostic

This is a staged experiment, not a benchmark result. It uses the same
5,000-row Fashion-MNIST input, CPU-prepared fuzzy graph, initialization,
400 epochs, 0.25 learning rate and seeds 4/17/42 for five optimizer routes:
the current CPU reference, all-CPU fixed-point updates, a split all-CPU
control, all-Metal scheduled updates, and the current CPU-warm/Metal hybrid.

The split all-CPU control checks whether continuation itself changes the
result. Comparing all-Metal with the hybrid isolates the effect of the CPU
warm phase. A sampled label silhouette and elapsed optimizer time are recorded
for each run, with a CSV saved after every case. The experiment must run only
after the active mass41 CPU4 t-SNE diagnostic has finished and all its owned
processes are gone. Keep the script, its output, and logs under Stefano on the
Mac; run with the source-locked `535d071` package library. Do not treat one
quality score as proof of backend correctness or manuscript performance.

The staged Mac script SHA-256 is
`ba3212bc107ac015615005bd3dac0b8cbdf34e4774c63dc0361128e0941e754d`.
Its library argument is restricted to
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-release-535d071-20261107/library`.
The second argument must be a new CSV path under Stefano. The experiment is
not running while the mass41 diagnostic remains active.
