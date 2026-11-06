# First two-GPU setup incident, 3 November 2026

The authorized Hugging Face job `tkcaccia/6ae9852e0e0338d1bb7ef8df`
started at 06:54:38 UTC and ended with `ERROR` at 06:56:05 UTC. Its log
verified the patch and test bundle hashes, then failed to unpack the test
archive: `tar (child): xz: Cannot exec: No such file or directory`.
No NCCL or package test ran; this is an image setup failure.

The short same-image CPU preflight job
`tkcaccia/6ae985c3c78863f9c631725b` completed at 06:58:32 UTC. It
confirmed Python 3.12.11 with `lzma`, `/usr/bin/git`,
`/opt/conda/condabin/mamba`, and `/usr/bin/tar`. The runner now uses Python
`lzma` to unpack both archives and plain `tar -xf` and `git apply`.
The replacement runner SHA256 is
`281c503aadc943e3b752033d5a725f9afd5b17055ce8c83aff9002a514173391`.
The source patch and test bundle hashes are unchanged.

The 30-minute timeout at US$3/hour limits a full two-GPU run to US$1.50.
The first failed run lasted under two minutes, so one bounded retry and
the CPU preflight remain within the approved US$2 total under the published
per-minute billing rule. The exact billed amount must be checked in the
Hugging Face account after completion.
