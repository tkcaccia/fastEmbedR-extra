# Resident CUDA t-SNE device-count candidate

The isolated package candidate `9b595b9` removes the fixed four-device
checks from resident full-data t-SNE and held-out landmark query
projection. It retains distinct, visible device validation and requires
at least one data row per shard. Native attraction workers, NCCL
communicators, and query shards already use dynamically sized vectors.
The package change includes a mocked eight-device public-API routing test.

This change has passed R parsing and `git diff --check` only. It has
**not** passed CUDA compilation, device execution, real-data quality,
memory, timing, or cleanup checks. Do not include it in the source-locked
manuscript cohort. The queued Hugging Face eight-A100 clustering job uses
an earlier source archive and cannot qualify this candidate.

The full-data optimizer still performs FFT repulsion on the first GPU;
each GPU performs a row shard of attraction. The complete layout and
optimizer state are replicated on each GPU. Thus, accepting more than
four devices is not proof of useful speedup or beyond-VRAM capacity.
Qualification must measure 2/4/8-device attraction, FFT time, total
runtime, per-device memory and work, trustworthiness and label quality,
distinct UUIDs, and owned-context cleanup on a fixed real input.

Follow-up candidate `c606545` also removes the four-device check from the
file-backed CUDA t-SNE planner, which calls the same dynamically sized
native optimizer. A direct pure-R check accepted eight devices for 24 rows
and rejected both empty owner shards and missing NCCL. R parsing and diff
checks passed. This is a planner check, not a file-backed GPU run. Such a
run must be qualified on a permitted machine; it is forbidden on UCT HPC.
