# Bounded multi-GPU clustering candidate, 4 November 2026

The isolated package candidate adds `gpu_storage = "stream"` to
`massive_cluster()` for symmetric file-backed CSR graphs, CUDA, two to four
devices, Louvain, and Leiden. Every GPU processes row and edge batches that fit an
explicit edge budget. Labels, degrees, community volumes, and the graph
remain in host storage; CPU contraction creates the next Louvain level.
Leiden refinement runs on CPU with a final connectivity audit.
Every accepted color phase is checked against exact graph modularity, and
the final labels undergo the package's independent C++ modularity audit.

This is **not yet device qualified**. The Leiden path is a hybrid of
multi-GPU local moves and CPU refinement. The route has no checkpoint or
resume support. It must never
run on the UCT HPC, where file-backed scientific work is prohibited.

The isolated CPU-only package build passed. The new R route and planning
tests passed, as did a real CSR contraction/remapping test with the GPU
local level mocked. Python CPU invariants passed on float32 and float64
CSR. The package source-style check passed. These checks do not establish
CUDA correctness, performance, or operation beyond combined physical VRAM.

`stream_run_20261104.py` is a prepared two-A10G qualification. It first
checks a small four-community graph with and without an initial parent
partition, then a 100,000-row graph whose CSR
file is larger than the combined **artificial 8 MiB CuPy pool limits**.
That is a controlled memory-bound test, not proof that the graph exceeds
the A10Gs' physical 48 GB combined VRAM. Both GPU PCI IDs, pool use,
all-row labels, and an independent modularity score are checked.
The runner keeps each worker and its children in one owned process group,
checks for surviving descendants, and uses bounded TERM/KILL cleanup on
failure or timeout. Its per-case deadlines total eight minutes, leaving
two minutes under the ten-minute server limit for startup and cleanup.

Submission awaits a raised Hugging Face spending cap. The previous
US$2 cap has approximately US$0.19 unverified headroom, and automatic
approval review rejected another paid job. The proposed pilot has a
10-minute timeout on two A10Gs; at the published US$3/hour price, the
runtime ceiling is about US$0.50 plus billable startup time.
