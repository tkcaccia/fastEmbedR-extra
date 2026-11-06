# Mac clustering allocation experiment, 5 November 2026

The candidate reserves bounded neighbor-label map capacity during parallel
file-backed Louvain and Leiden preparation. It changes four C++ lines and
does not change the update order. Both builds used the same package source
apart from this change. Runs used existing file-backed graphs under Stefano,
four CPU workers, the same seed, graph, pass count, and memory budget.

| Method | Graph | Baseline 1 | Candidate 1 | Candidate 2 | Baseline 2 |
| --- | --- | ---: | ---: | ---: | ---: |
| Louvain | 100k x 30 | 0.428 | 0.413 | 0.414 | 0.429 |
| Louvain | 50k x 200 | 0.788 | 0.767 | 0.765 | 0.777 |
| Leiden | 100k x 30 | 0.847 | 0.820 | 0.820 | 0.849 |
| Leiden | 50k x 200 | 1.625 | 1.609 | 1.610 | 1.623 |

Times are elapsed seconds. Each four-run group had identical label SHA-256,
community count, and modularity. The installed candidate passed focused
`test-massive-louvain.R` and `test-massive-leiden.R` under Mac R 4.6. This
small gain is repeatable in this paired check, but four workers still trail
one worker on both graphs; no multi-CPU speedup is claimed.

Mac build and full logs:
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-reserve-20261105`.
The four result tables are preserved in `pairs.tar.gz` here. SHA-256:

- C++ source: `724900caff4b82b86a641c88c2ccb629be198c055e1a4621bb76bced20d3aa7c`
- Comparison script: `8b33a418d8f02e15ffa0c197b9f596a5708a567e51c78bdd24a4e699a60e3e77`
- Result archive: `5a0a81faa0af06341c93eb9dbc726403386f9916ea6b378f3ae271e8ed284344`
