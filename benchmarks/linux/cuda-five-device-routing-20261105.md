# File-backed CUDA clustering: five-device routing check

The isolated package candidate at
`in-progress/cuda-stream-persistent-20261105` no longer imposes an
arbitrary four-device ceiling in its R stream planner or Python worker.
The route still requires at least two CUDA devices, distinct visible
device identities, and no more worker partitions than graph vertices.
It keeps bounded per-worker GPU batches and shared file-backed state.
Worker shutdown now uses three global five-second windows for graceful,
terminate, and kill stages, rather than a ten-second wait per worker at
each stage. Queue stop messages have a 0.1-second bounded send attempt.
This prevents cleanup time growing by 30 seconds for each added GPU.

Checks on 2026-11-05:

- `Rscript tools/check_source_style.R`: passed.
- A direct R source check planned five distinct devices and UUIDs: passed.
- CPU-side Python worker tests, including five-partition metadata and
  an eight-worker global shutdown-deadline simulation: six tests passed
  with plugin autoload disabled.
- Python and R syntax checks: passed.

This is **routing and lifecycle-fixture evidence only**. No five-GPU
hardware test, physical over-combined-VRAM test, quality comparison, or
performance result exists. The separate four-L4 source-locked Hugging Face
job remains independent of this later code change. Do not publish this
candidate or claim five-device support until a new immutable build passes
real-device quality, memory, ownership, and cleanup checks. Other CUDA
routes still contain four-device limits and require separate redesign.
