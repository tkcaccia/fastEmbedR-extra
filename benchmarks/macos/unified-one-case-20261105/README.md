# Source-locked Mac resident one-case runner

This candidate runner admits one resident, full-data CPU or Metal case at a
time. It checks the manifest, input, package source archive, and installed
library before calculation. It records stage times, output quality, peak RSS,
swap, process cleanup, and source/input identities. File-backed and landmark
cases require separate controlled lanes. A deliberately wrong input digest
was rejected before a scientific calculation.

The remote source-locked runner used for the cases below is in
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-current-one-case-20261105`.
Its Python runner digest is
`19add560dc73468551b803ffef08592f29dd75ef2bdbd4215333b25b4ca8a828`;
its R worker digest is
`534f20455a64846e768d1b24dad238bfd8dcac20c13357979c10923cb7d3506c`.
The installed package source archive digest is
`18902d45dd0a6d0278f52d3712e8892a38d6ec16516644fc9ee2114f5be92973`
and the DLL digest is
`946fc2ecf073a0e0863ad8a709fa6d5911cfece8f2fe60e88cd3245d0f43d9ce`.
The COIL20 input digest is
`8e53030869bcfbc228edc06ca970e69b78ddae13fb188327e8899194d5841d66`.

## COIL20 paired 2D UMAP development cases

All six cases used all 1,440 rows, 16,384 input columns, a rank-30 CPU
preprocessing step, one scientific fit, the public `umap()` API, and a
600-row quality sample. Every result reported the requested effective
backend, terminal success, clear owned process group, and unchanged
7.69 MB system swap. Cases were run serially on the Mac.

| Seed | Backend | Fit seconds | Peak RSS MiB | Trustworthiness | Label accuracy |
| --- | --- | ---: | ---: | ---: | ---: |
| 4 | CPU, 1 core | 0.749 | 614.0 | 0.9797 | 0.8883 |
| 4 | Metal, 1 GPU | 0.367 | 625.0 | 0.9793 | 0.8950 |
| 17 | CPU, 1 core | 0.735 | 613.9 | 0.9826 | 0.8500 |
| 17 | Metal, 1 GPU | 0.367 | 624.7 | 0.9817 | 0.8450 |
| 42 | CPU, 1 core | 0.790 | 614.0 | 0.9810 | 0.8483 |
| 42 | Metal, 1 GPU | 0.362 | 625.0 | 0.9833 | 0.8483 |

These are development cases, not manuscript performance estimates. They
compare three seeds but only one repetition per seed, one dataset, and one
method. The runner has not yet qualified all public methods, multi-CPU
scaling, file-backed routes, or the eleven-dataset panel. Its local policy
was subsequently tightened to reject Boolean values for the scientific-fit
and warmup counts; the remote source-locked cases above used integer values.

The separate Fashion-MNIST fixed-graph Metal UMAP quality failure remains
unresolved and is not overridden by these COIL20 results.

## Other COIL20 method qualification

The first Metal PCA case failed before result writing because the benchmark
worker demanded the literal backend string `metal`. The public PCA result
correctly reports `metal_mps_rsvd`, with engine `native_metal_mps`. This
was a benchmark audit defect, not a package PCA failure. The failed case and
its log remain in the original remote results. A new source-locked runner
version is under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-current-one-case-v2-20261105`.
Its R worker SHA-256 is
`011970d97601a88c80f9dfef2ad920749c435f0c66111a1bfe2ad0f1de9378d5`;
its Python admission policy SHA-256 is
`13c7723adc4cca3334fa3b6669a22b92db9b97ef85dee8d2db6ebe296078345e`.
It accepts only Metal-prefixed PCA metadata together with the native MPS
engine identity. The package and COIL20 input identities are unchanged.

| Method | CPU fit s | Metal fit s | CPU peak RSS MiB | Metal peak RSS MiB | Quality observation |
| --- | ---: | ---: | ---: | ---: | --- |
| PCA, rank 2 | 0.067 | 0.087 | 505.4 | 675.1 | Singular values differ by 0.04% and 0.24% |
| t-SNE, 2D | 3.521 | 0.556 | 613.0 | 687.7 | Trustworthiness 0.9874 / 0.9873 |
| Leiden | 0.011 | 0.062 | 551.9 | 561.2 | ARI 0.6675 / 0.6676 |
| Louvain | 0.006 | 0.029 | 551.9 | 558.5 | ARI 0.6780 / 0.6694 |

Each case used seed 4 and one repetition. CPU PCA is from the first runner
and Metal PCA from the corrected runner; they are not a publication timing
pair. The remaining three methods used the corrected runner for both
backends. All eight cases completed, identified the requested backend,
reported unchanged swap, and cleared their owned process groups. The Metal
Leiden and Louvain graph path also passed the no-fallback check. These
development checks do not establish performance across datasets or cores.

## Three-dimensional and four-core checks

Runner v3 in
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-current-one-case-v3-20261105`
adds PCA and clustering output-shape checks and records the PCA effective
CPU worker count. Its R worker SHA-256 is
`eae0603ff0681d7473ede3af4e73d108eb4c0922592d427f35ff5eeec4931762`.
The same package and COIL20 input were used. Each case used seed 4, one
repetition, and ran alone on the Mac. All nine cases completed with clear
owned process groups and unchanged swap.

| Method | Requested backend/cores | Effective CPU workers | Fit s | Peak RSS MiB | Quality |
| --- | --- | ---: | ---: | ---: | --- |
| t-SNE 3D | CPU / 1 | 1 | 2.527 | 612.8 | Trust 0.9864, label 0.8633 |
| t-SNE 3D | Metal / 1 | n/a | 1.316 | 644.6 | Trust 0.9870, label 0.8617 |
| UMAP 3D | CPU / 1 | 1 | 0.818 | 614.7 | Trust 0.9824, label 0.8967 |
| UMAP 3D | Metal / 1 | 1 | 0.430 | 625.0 | Trust 0.9824, label 0.8983 |
| PCA rank 2 | CPU / 4 | 4 | 0.044 | 507.8 | Singular values match CPU 1-core case |
| t-SNE 2D | CPU / 4 | 2 | 2.274 | 613.2 | Trust 0.9874, label 0.8667 |
| UMAP 2D | CPU / 4 | 4 | 0.152 | 614.0 | Trust 0.9755, label 0.8917 |
| Leiden | CPU / 4 | 4 | 0.027 | 552.1 | ARI 0.6607, modularity 0.9030 |
| Louvain | CPU / 4 | 4 | 0.018 | 552.1 | ARI 0.6595, modularity 0.9028 |

The effective two workers for four-core t-SNE is the package's recorded
value, not an assumption that four cores were fully used. Four-core UMAP
trustworthiness was 0.0042 below the one-core seed-4 run; this difference
needs repeated paired checks before any equivalence claim. Four-core
clustering was slower on this small graph. These cases qualify runner
routes, not the formal multi-CPU scaling grid.
The Metal t-SNE result writes a missing CPU-worker count as `"NA"`; this
is a benchmark serialization defect to fix in the next runner version.

## Corrected metadata and same-version CPU UMAP pairs

Runner v4 in
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-current-one-case-v4-20261105`
normalizes missing effective-worker metadata to JSON `null`. Its R worker
SHA-256 is
`e772286c53536e009471f8b8a5ae2f09db67f01e161f8aee892a46d669619da4`.
A new Metal 3D t-SNE case completed and reported `null`, rather than
`"NA"`, for the inapplicable CPU-worker count. Its trustworthiness was
0.9870 and its peak RSS was 640.9 MiB. The v3 record is preserved.

The v4 runner then completed one- and four-core 2D CPU UMAP cases at
seeds 4, 17, and 42, using the same package build and input for all six
cases. Actual effective workers matched the request, all process groups
cleared, and system swap was unchanged.

| Seed | One-core fit s | Four-core fit s | One-core trust | Four-core trust |
| --- | ---: | ---: | ---: | ---: |
| 4 | 0.757 | 0.152 | 0.9797 | 0.9755 |
| 17 | 0.757 | 0.152 | 0.9826 | 0.9789 |
| 42 | 0.779 | 0.152 | 0.9810 | 0.9829 |

Mean fit time was 0.764 s on one core and 0.152 s on four cores.
Mean trustworthiness was 0.9811 and 0.9791, respectively. The paired
trustworthiness changes were -0.0042, -0.0037, and +0.0019. This is a
small-data qualification check; more repetitions and datasets are needed
for a manuscript scaling or quality claim.
