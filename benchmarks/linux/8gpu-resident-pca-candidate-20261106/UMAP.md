# Resident CUDA UMAP device-count candidate

The isolated package candidate `763b488` removes the fixed four-device
checks from resident full-data UMAP and resident landmark UMAP query
projection. It retains validation of distinct, visible devices and a
nonempty row shard per device. The native full-fit optimizer already uses
dynamically sized per-device contexts, deltas, communicators, and futures;
the query projector uses dynamically sized shards and workers.

This is **not yet device-qualified**. The local PC has no usable CUDA build
or eight-GPU device. R source and the added eight-device mocked public-API
routing test parse, and `git diff --check` passes. The actual R test file,
CUDA compile, eight-device execution, real-data quality, memory, timing,
and cleanup remain to be checked on source-locked hardware. The queued
Hugging Face eight-A100 clustering job uses an earlier package source and
cannot qualify this UMAP change.

The resident full-fit UMAP optimizer still replicates the complete 2D/3D
layout on every GPU and builds its KNN graph in host RAM. Removing the
device-count check does not establish beyond-VRAM scaling. Release claims
must wait for an actual 2/4/8-device test that records distinct UUIDs,
positive work on each GPU, trustworthiness and label quality versus a
fixed input/reference, peak host and per-GPU memory, runtime by stage,
and empty owned GPU contexts after completion.
