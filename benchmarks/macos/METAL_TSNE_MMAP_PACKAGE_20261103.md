# Experimental 3D Metal t-SNE mapped-graph route, 3 November 2026

## Source and build

- Package candidate: `in-progress/metal-landmark-3d-20261102` in the local
  project. This is an isolated, uncommitted worktree, not a release.
- Baseline Mac copy and installed library:
  `/Users/silvanopiazza/Documents/Stefano/metal-tsne-mmap-package-20261103`.
  The latest deterministic candidate is isolated at
  `/Users/silvanopiazza/Documents/Stefano/metal-tsne-fixed-near-20261103`.
- The native optimizer maps each complete CSR file read-only with
  `MAP_SHARED` and exposes its pages to Metal. It supports 3D only. It is
  file-backed but does **not** stream bounded graph chunks. Each file must
  fit one Metal buffer, and the layout and optimizer state are resident.
- R API dispatch, Metal backend checks, resource estimates, restart state,
  generated Rcpp registration, help page, and capability docs were updated.
- Current source identities: `R/massive_tsne_optimizer.R` SHA256
  `1afcec965be5d287c2cc887bb77fe70b265a2ddfb537f93ba3daaff149b46bca`;
  `src/embedding_metal_impl.mm` SHA256
  `204a826b3402da35f0be2b567aaa257ffe39de73f034977abae30352ad223c07`;
  `src/tsne_fft_3d_metal.h` SHA256
  `b7e170bbe5335df78730afde52a08977ea1cfa3d9dd09c5f2d007901db236c62`.

## Tests

- Mac package compilation and installation succeeded in the isolated library.
- The focused 16-row graph test passed 10 assertions, including intentional
  interruption after a committed snapshot, restart from iteration 2, and
  comparison with an uninterrupted result. See
  `metal_tsne_mmap_resume_20261103.log`.
- The earlier focused and resident 3D regression batch passed 82 cumulative
  assertions with no failures, warnings, or skips. See
  `metal_tsne_mmap_regression_20261103.log`.
- Local `Rscript tools/check_source_style.R` and `git diff --check` passed.

## Bounded 5,000-row probe

The script `metal_tsne_mmap_5k_probe_20261103.R` constructed a temporary
synthetic ring affinity graph with 300,000 directed edges, ran 100 iterations
on each backend, and deleted its generated graph and layouts on exit. The
final log is `metal_tsne_mmap_probe5k_20261103.log`.

| Measure | CPU, one worker | Metal |
| --- | ---: | ---: |
| Optimizer wall time | 12.05 s | 0.233 s |
| Mean near/far layout distance ratio | 0.02421 | 0.02455 |

The Metal fit reported `native_metal_fft_graph_mmap`, read-only graph access,
and a 64-cell FFT grid. The aligned coordinate RMS difference from CPU was
0.801 relative to CPU RMS. The ring geometry check is exploratory and does
not establish equivalent embeddings or accuracy on a real dataset. This is
one synthetic run, so its timing is not a publication speedup estimate.

## Real FashionMNIST 5,000-row pilot

The script `metal_tsne_mmap_fashion5k_20261103.R` used the existing
FashionMNIST 5,000-row float32 dataset (SHA256
`bc6530145a93ecb26e6484d9cabf8c4e994ba86c75bae5ce3e3db0069ffdddd6`).
Its exact Metal 90-neighbor graph was converted to a shared 30-perplexity
symmetric affinity graph with 650,676 directed edges. CPU and Metal used the
same graph and random 3D start for each seed, with 50 early and 200 normal
iterations. The 30-neighbor preservation scorer used native exact search
over the final 3D coordinates; label silhouette used a fixed 1,000-row
sample. The script SHA256 is
`4bc9a41719a3bd0df7d0468c7e8219d4e0654d943e932fe525ea356662b26434`.

| Seed | CPU fit s | Metal fit s | CPU silhouette | Metal silhouette | CPU Preserve@30 | Metal Preserve@30 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 30.886 | 0.422 | 0.18716 | 0.20070 | 0.49673 | 0.49690 |
| 17 | 31.032 | 0.434 | 0.19081 | 0.18074 | 0.49612 | 0.49697 |
| 42 | 31.025 | 0.422 | 0.19051 | 0.17610 | 0.49619 | 0.49555 |

The three exact-score logs are
`metal_tsne_mmap_fashion5k_exact_seed{4,17,42}_20261103.log`.
Median optimizer time was 31.025 seconds on one CPU worker and 0.422 seconds
on Metal. Graph construction, input KNN, scoring, and package setup were
outside these times. The paired silhouette differences vary by seed, from
-0.01440 to +0.01355; Preserve@30 differs by at most 0.00086. This is
promising engineering evidence, but the fit order was fixed and a single
small real dataset cannot establish publication speed or quality parity.
No temporary graph or layout directory remained after the runs.

## Deterministic 3D grid correction

Five fits from the **same** 70,000-row graph and initialization exposed a
repeatability defect in the original float-atomic Metal grid: the final
sampled silhouette ranged from 0.04826 to 0.09931, and all five layout
checksums differed. One-step outputs already differed. The fixed graph and
start had matching MD5 checksums across the diagnostic runs; see
`metal_tsne_mmap_fashion70k_fixed_graph_repeats_20261103.log` and
`metal_tsne_mmap_fashion70k_firststep_repeats_20261103.log`.

The Mac Metal runtime rejected 64-bit atomic addition. The candidate now
uses two 32-bit integer atomics with carry to accumulate a scaled 64-bit
grid mass, followed by conversion to float for the FFT. Nearby-pair
corrections also accumulate scaled 64-bit integers within each row, making
their sums independent of linked-list visitation order. The intermediate
grid-only change made five one-step outputs identical but left final
coordinate variation; see `metal_tsne_fixed_grid_firststep_20261103.log`
and `metal_tsne_fixed_grid_full250_20261103.log`.

With both changes, five complete 250-iteration fits from one fixed graph
and start produced the **same layout MD5**
`ef88da8955a180b7e5944d6f2789541b`, with zero maximum coordinate
difference and sampled silhouette 0.06594807. Each fit took 9.34--9.50
seconds. The earlier float-atomic route took about 3.1--3.5 seconds in the
same fixed-graph diagnostic. The corrected route passed 82 cumulative
focused/resident Metal assertions with no failures, warnings, or skips.
See `metal_tsne_fixed_near_full250_20261103.log` and
`metal_tsne_fixed_near_regression_20261103.log`.

On the corrected route, the 70,000-row graph had 3,362,694 directed edges.
The measured peak process footprint was 727,991,160 bytes with zero swaps;
the conservative planner estimated 1,106,803,384 bytes. Its temporary
graph and layout were removed after measurement. See
`metal_tsne_fixed_near_fashion70k_memory_20261103.log`.

The same three FashionMNIST 5,000 seed pairs were rerun with exact scoring:

| Seed | CPU fit s | Corrected Metal fit s | CPU silhouette | Metal silhouette | CPU Preserve@30 | Metal Preserve@30 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 30.908 | 0.489 | 0.18716 | 0.18970 | 0.49673 | 0.49371 |
| 17 | 30.970 | 0.483 | 0.19081 | 0.18010 | 0.49612 | 0.49543 |
| 42 | 31.056 | 0.475 | 0.19051 | 0.17755 | 0.49619 | 0.49591 |

The median optimizer times were 30.970 seconds for one CPU worker and
0.483 seconds for corrected Metal. The paired quality difference remains
mixed, with the largest silhouette decline 0.01295 and largest
Preserve@30 decline 0.00302. These are exploratory comparisons, not an
all-dataset quality or publication-speed qualification. The logs are
`metal_tsne_fixed_near_fashion5k_seed{4,17,42}_20261103.log`.

## Remaining qualification

The route still needs quality checks across more datasets, independent
timing repeats and a million-row graph trial, and explicit preflight of the
device buffer and shared-memory limits. A bounded-chunk streaming route was
subsequently added and checked separately; see
`metal-tsne-stream-20261103/README.md`. A 2D mapped and streamed route was
subsequently implemented and checked separately; see
`metal-tsne-fixed2d-20261103/README.md`. The postponed Deep1B 100M run has not been started with
either candidate.

The two temporary graph folders left by the first probe script were removed.
The final script verified cleanup. Generated compiler objects were removed
from the Mac source copy after installation, reducing the isolated folder
from 60 MB to 12 MB; the tested installed package and logs were retained.
