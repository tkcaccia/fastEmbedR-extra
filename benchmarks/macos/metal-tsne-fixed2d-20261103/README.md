# Experimental 2D Metal file-backed t-SNE, 3 November 2026

The isolated package candidate `in-progress/metal-landmark-3d-20261102` now
supports 2D Metal t-SNE with either a mapped read-only CSR graph or bounded
SSD graph-chunk uploads. The public `massive_tsne_optimize()` route accepts
`graph_access = "mmap"`, `"stream"`, or `"auto"`; it retains the layout and
optimizer state in unified memory. The streaming option bounds graph uploads,
not the entire working set. Checkpoint/resume was exercised in the focused
package test. It does not establish feasibility at 100 million rows.

## Reproducibility and checks

- The tested Mac installation is
  `/Users/silvanopiazza/Documents/Stefano/metal-tsne-fixed2d-20261103/Rlib`;
  installed `fastEmbedR.so` SHA256:
  `a96443fd63da024ac3028a90685ff1460a11f4f81ce1b08016319ae0af942138`.
- Candidate source SHA256: `R/massive_tsne_optimizer.R`
  `0c56400d555eccb0ef1b9230909e8b12f49e45fefb9db571c462da820c888f84`;
  `src/embedding_metal_impl.mm`
  `db0e498afbbd233f5f71dd575b6c74a55902bb7820bcb4bdcad5576ed1343ad7`;
  `src/tsne_fft_2d_file_metal.h`
  `875fb2483244e11ffdb479c70724c1a0b98cc7ced69d35e60c965b6fdc4887cc`.
- `focused_test_final.log`: 31 passes, no failures, warnings, or skips;
  SHA256 `07ab56e04785fdebbdd3b9366e8b8c8ab9971e2221db5d6e4dd84a8848ad8a74`.
- `resident_regression.log`: 45 passes and five CUDA skips in the 3D t-SNE
  test, then 82 passes in Metal stages; no failures or warnings;
  SHA256 `43671abe5e5a437ecf41e333e143f0a3846a156586f11d60346824096e695a46`.

An earlier 2D implementation used order-dependent float atomics and varied
between fixed-graph runs. Its negative log is retained in the sibling
`metal-tsne-file2d-20261103/` folder. The revised file-backed 2D route uses
scaled integer grid accumulation. The resident 2D path was not changed to
this grid scheme.

## Paired exploratory fits

Fashion-MNIST 5,000 used one exact Metal 90-neighbor graph, the same 2D
random start for each seed, perplexity 30, and 50 plus 200 iterations. The
timings below are optimizer times only. Preserve@30 and silhouette used
fixed evaluation samples.

| Seed | CPU 1 worker (s) | Metal mapped (s) | Metal streamed (s) | CPU silhouette | Metal silhouette | CPU Preserve@30 | Metal Preserve@30 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 17 | 2.302 | 0.363 | 0.838 | 0.1186067 | 0.1110343 | 0.45682 | 0.45784 |
| 4 | 2.322 | 0.366 | 0.832 | 0.1353494 | 0.1384222 | 0.4541667 | 0.4571467 |
| 42 | 2.322 | 0.358 | 0.836 | 0.05335665 | 0.06327447 | 0.4582 | 0.4559333 |

For each seed, three mapped and two streamed runs gave an identical layout
MD5. The logs are `fashion5k_2d_fixed_seed{17,4,42}.log`.

Fashion-MNIST 70,000 used one exact 30-neighbor graph with 3,362,694
directed edges, perplexity 10, the same random start, and 50 plus 200
iterations. CPU one-worker optimization took 12.039 s (sampled silhouette
0.0152564), Metal mapped 0.365 s (0.02480425), and Metal streamed with
262,144-edge chunks 1.482 s (0.02480425). Mapped and streamed coordinates
had identical MD5 `294c15b849a82a05f42355db205326af`. Whole-script
`/usr/bin/time -l` reported 429,015,040 bytes maximum resident set size,
721,945,488 bytes peak footprint, and zero swaps. Those memory values combine
all three fits, so they cannot be attributed to any one route. See
`compare_fashion70k_2d.R` and `fashion70k_2d.log`.

USPS 11,000 provides a second dataset check. It used one exact Metal
90-neighbor graph with 1,398,470 directed affinity edges, seed 17, and
50 plus 200 iterations. Two mapped fits (0.274 and 0.265 s) and one
streamed fit (1.244 s) had identical layout MD5
`fe479691d6fcec72a258dc5afbc674b7` and sampled silhouette 0.1716051.
The CPU one-worker fit took 3.282 s and had sampled silhouette 0.1560401,
but CPU used a 128-cell FFT grid while Metal used 256, so this is a route
check rather than a controlled CPU/Metal quality comparison. The whole
script reached 245,301,248 bytes maximum resident set size, a 551,633,736
byte peak footprint, and zero swaps; again these are not per-route peaks.
The input, graph, and initial-coordinate MD5 values are in `usps11k_2d.log`
(SHA256 `061499ba508cdcc9b21e615f23c8dd5d19f763a89e2eaeb5f177b393355cd78e`).
The test script is `compare_usps11k_2d.R`; its temporary graph and layouts
were removed after completion.

## Limits and next checks

These fixed-graph checks do not measure end-to-end KNN or affinity building,
per-method peak memory, independent repeated timings, large-scale throughput,
or broad dataset quality. For cross-backend quality comparisons, hold the FFT
grid and other algorithmic settings fixed or explicitly report each difference.
Before using the route in manuscript figures, run
the source-locked panel under a common input, seed, quality, and timing
protocol after its suspension is explicitly lifted. Qualify graph and device
buffer limits before a 10-million-row or larger run. The Deep1B 100-million
stress test remains postponed.

The Mac source folders were reduced to about 12 MB each after installation;
the installed library and evidence logs remain under Stefano. Temporary
graph and layout folders from these checks were removed.
