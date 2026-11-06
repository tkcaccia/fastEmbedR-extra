# Source-locked HPC image candidate, 4 November 2026

Package source: `tkcaccia/fastEmbedR` branch
`codex/implementation-qualification-20261104`, commit
`b8251168e3b77093452876c10e1a79861d9660e5`. This is a qualification
candidate, not a release or a manuscript benchmark result. The original
repositories and the older HPC image remain unchanged.

The definition derives from the verified 29 October HPC image, whose SHA-256
is in `source-identity.txt`. The three reviewed R source archives are listed
in `SHA256SUMS`; they were staged separately on the HPC under
`/scratch/firenze/NN/singularity/candidate_b825116_20261104/release_inputs`.
The CPU-only image build is Slurm job `1570377` on the `ada` partition.

The build checks input hashes and the exact commit, compiles with CUDA and
NCCL enabled, and writes a separate immutable candidate SIF. It does not
run GPU calculations. The candidate requires a resident-memory-only,
fail-fast L40S pilot with owned-process and GPU-context cleanup evidence
before any wider HPC GPU benchmark. No file-backed or SSD-streaming
scientific calculation is permitted on the HPC. Do not use the archived
`test_candidate_gpu.R` or its old smoke submitter for this pilot; those
routes create streamed inputs.

CPU build job `1570377` completed successfully. The image SHA-256 is
`144b878f42b8c10f2dc9bc3ee422c51caf5a090049c0f89027fdc27ad1f34773`.
The embedded commit/source labels, R package import, and NCCL build flag
were verified. CPU-only Slurm signal route job `1570378` was submitted to
check real scheduler warning delivery before the GPU pilot.
It completed successfully and recorded `SCHEDULER_WARNING_RECEIVED SIGUSR1`.
The first L40S submit was rejected by Slurm before scheduling because the
script omitted the `l40sfree` account. The corrected, separately saved v2
script submitted pilot job `1570379`; it initially waited on priority.

The original `singularity/fastembedr_cuda.def` and stable images are not
modified. Record the final SIF hash, build log, pilot identities and all
terminal outcomes here after they are available.

The staged first device pilot is a single 160-row, resident-memory 3D UMAP
case with 80 landmarks on two allocated L40S GPUs. Its runner validates the
image checksum, Slurm GPU allocation and UUIDs, samples compute contexts at
0.2 Hz, enforces a three-minute application deadline and bounded process
group shutdown, and verifies that assigned-device contexts clear. The Slurm
job has a ten-minute limit and a two-minute warning. Six local synthetic
lifecycle checks passed, including a child failure, an exited parent with
a live descendant, a child ignoring TERM, a persistent context, missing
telemetry, and the warning signal. These checks do not substitute for the
real-device cleanup audit, so no broader campaign follows automatically.
