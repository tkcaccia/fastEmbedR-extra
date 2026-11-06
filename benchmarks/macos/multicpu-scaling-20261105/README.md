# Mac file-backed clustering CPU scaling, 5 November 2026

The isolated package candidate was tested on Silvano's Mac using two
existing file-backed fuzzy graphs under Stefano. No graph input was copied.
The first-pass Louvain scheduling improvement was present. Each cell is one
elapsed-time observation, so these are development measurements rather than
publication benchmark estimates.

| Method | Graph | 1 CPU | 2 CPUs | 4 CPUs | 8 CPUs | 16 CPUs |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Louvain | 100k vertices, 30 neighbors | 0.342 | 0.423 | 0.424 | 0.451 | 0.520 |
| Louvain | 50k vertices, 200 neighbors | 0.709 | 0.772 | 0.763 | 0.782 | 0.794 |
| Leiden | 100k vertices, 30 neighbors | 0.693 | 0.841 | 0.842 | 0.877 | 0.964 |
| Leiden | 50k vertices, 200 neighbors | 1.542 | 1.647 | 1.629 | 1.647 | 1.686 |

Timings are seconds. The reported effective worker count reached each
requested core count. Within each method and graph, label SHA-256,
community count, and modularity were identical at every core count. The
parallel proposal stage remains slower than the one-core path on these
graphs, despite the earlier first-pass improvement. The next change should
target per-batch thread startup and per-row allocation; it needs a paired
quality and memory check before any speed claim.

The complete result is `metrics.csv`. The Mac working directory is
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-scaling-20261105`.
Its first script stopped after five Louvain cases because Leiden does not
return a `moves` field; the versioned continuation recorded `NA` for that
optional field and finished the remaining cases without replacing outputs.
The complete CSV SHA-256 is
`922ea493a07dd30ea587f0502d4c011515f1f45cd3eafd8d3714f8f59ee353d5`.
The continuation script SHA-256 is
`6df4ec72a49c3bbd3d03ee73a940937881739eab41b45867d240235f34278397`.
