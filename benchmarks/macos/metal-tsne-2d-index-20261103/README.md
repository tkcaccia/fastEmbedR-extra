# 2D Metal t-SNE CSR index preparation, 3 November 2026

The isolated package candidate now gives both 2D Metal t-SNE epoch
kernels an explicit CSR neighbor index base. Existing resident fits pass
zero; the planned file-backed graph path will pass one for its on-disk
one-based indices. All three resident update dispatches now bind the
base parameter. The kernels already accept a first row and edge offset,
which permits row-aligned graph chunks without changing the 2D FFT
repulsion method.

This is a prerequisite for 2D file-backed t-SNE, **not** the complete
route. No public 2D file-backed Metal fit was enabled by this change.

The Mac build and installed-package `test-tsne-fft-3d.R` passed 45
assertions with no failures or warnings; five CUDA-only checks were
skipped. The test log is `tsne_regression.log`, SHA256
`67ebec1817bd4d447f93d794de814eb6d9b245f6f7d2b62d94e5e4386e4ef3dd`.
The installed Mac library at
`/Users/silvanopiazza/Documents/Stefano/metal-tsne-2d-index-20261103/Rlib`
has SHA256
`0c9529e6b702079ac46fd2cbf85a2aa7782c2812d3092863b11114591f1f9251`.
The source file `src/embedding_metal_impl.mm` has SHA256
`36d8f97d3a627953cca75a4affdbe4d60b032244e18f466a238770b3931a52d9`.
Local source style and `git diff --check` passed. Generated compiler
objects were removed after installation; the Mac folder uses 12 MB.

Next: connect the existing 2D FFT loop to mapped and streamed graph
inputs, write 2D output and restart state, then compare against the
resident 2D route and CPU on real datasets. The source-locked Mac panel
remains suspended under the user's later instruction.
