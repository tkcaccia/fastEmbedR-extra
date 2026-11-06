# Two-A10G bounded CUDA clustering qualification, 4 November 2026

This is development evidence for the isolated
`inst/python/massive_cuda_stream_cluster.py` candidate. It is not a
publication benchmark or proof that a graph larger than physical combined
GPU memory can be clustered efficiently.

The source bundle SHA-256 was
`2c581a73a5d2d060c782d75c0fa389123a428577aabb40d1c233c547e8f71da6`.
The worker SHA-256 printed by the job was
`8bcd8e30ff7937d9c852ffdfbb99dc3cef4433cef7e10f89a83062438cbb108d`.
The job used two NVIDIA A10G devices, a RAPIDS CUDA 12.8 image, a ten-minute
server timeout, and a bounded runner with owned-process-group cleanup.

The first [versioned job](https://huggingface.co/jobs/tkcaccia/6aeba22ec78863f9c632f83e)
failed before GPU calculation: the base image lacked the `xz` executable
needed by `tar -xJf`. Its archive checksum had passed. The failed log is
`v1-terminal.log`. No scientific output from that job is counted.

The corrected [v2 job](https://huggingface.co/jobs/tkcaccia/6aeba383c78863f9c632f91d)
used Python's built-in `tarfile`/LZMA extraction and completed. Its terminal
log is `v2-terminal.log`. The two distinct GPU PCI IDs were
`0000:00:1B.0` and `0000:00:1C.0`; both devices reported work.

| Case | Result |
| --- | --- |
| 12 vertices, four disconnected communities | Four correct communities; modularity 0.75 matched an independent scorer. |
| 12 vertices with an initial parent partition | Four correct communities; initial-partition use reported; modularity 0.75. |
| 100,000 vertices, 32 neighbors | 26,400,008 graph-file bytes exceeded the artificial 16 MiB combined CuPy pool limit. Each GPU's recorded peak pool use was 1,360,384 bytes. The independent modularity score matched 0.21986924. |

The large fixture used one local-move pass and yielded 12,488 communities;
its low modularity is not evidence of good clustering quality. The memory
test proves bounded batches under a controlled GPU pool limit, not a graph
larger than the two A10Gs' combined physical VRAM. No SSD-streaming science
was run on the UCT HPC.

Next qualification: use an independent real-data graph and multiple passes;
measure host RAM, wall time, actual per-device VRAM, quality versus resident
Louvain/Leiden and igraph, then stress beyond a physically verified VRAM
budget on a permitted non-HPC machine. The hybrid Leiden path additionally
needs CPU-refinement and final connectivity checks on device output.

## Persistent-worker v3 qualification, 5 November 2026

The [v3 two-A10G job](https://huggingface.co/jobs/tkcaccia/6aebaf980e0338d1bb804124)
completed with `FASTEMBEDR_PERSISTENT_TWO_GPU_V3_PASS`. Its terminal log is
`v3-terminal.log`. The transferred source archive passed SHA-256 verification
(`7fd737bc9fd8dd62a79af1010d657db36b041e1ec8e838fe1b254e3769fae928`);
the new worker SHA-256 was
`17d9417d6882d3df821853ba608c27f942a7ae332427e833c9121a51eda85f99`.
Two distinct A10G UUIDs were recorded and two persistent GPU processes
started. Both GPUs reported bounded batch work.

On the 12-vertex fixture, the prior worker took 13.185 seconds and the
persistent worker 1.069 seconds; both gave four communities, modularity
0.75, and identical label hashes. On the 20,000-vertex fixture, times were
26.355 and 1.337 seconds with the same 2,432 communities, modularity
0.23976658, and identical label hashes. The 100,000-vertex fixture took
1.470 seconds with the persistent worker; its 26,400,008-byte graph file
exceeded an artificial 16 MiB combined CuPy pool limit, while each GPU's
recorded peak pool was 1,360,384 bytes. That is evidence of bounded device
batches, not a graph larger than the physical combined A10G memory.

These are synthetic development fixtures. Startup dominates the smaller
cases, and the 100,000-vertex fixture used one local-move pass. There is no
claim yet about real-data quality, physical over-VRAM scale, or publication
performance. The main package candidate has not incorporated the v3 worker.
Further paid Hugging Face jobs require a verified remaining budget.
