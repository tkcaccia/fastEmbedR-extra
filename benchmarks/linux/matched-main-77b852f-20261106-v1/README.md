# Matched resident CPU benchmark: fastEmbedR 77b852f

This plan uses package main commit
`77b852fc496ad4665969c4f6771088f5b98da4fe` and immutable HPC image
SHA-256 `ca7c58b98c180571e3a103258598ad7dbcb4354fb1abde3fc319aab2bc004b6b`.
It is a new cohort separate from the running `afeaffc` and `7c68bc2` jobs.
Those results and failures remain intact; methods from different source
versions must not be pooled in a manuscript comparison.

The planner expands the reviewed 77-case CPU4 panel to 462 cases: eleven
datasets, PCA, 2D/3D t-SNE, 2D/3D UMAP, Leiden and Louvain, and 1, 2, 4,
8, 16 and 32 requested cores. Every case is full-data, resident, CPU-only,
nonspilling, with one fit per allocation. The runner checks the raw input
SHA-256 on a compute node, route and output identity, effective CPU worker
count, quality, timings and job-cgroup memory. The eight-core COIL20 2D/3D
t-SNE pilots passed independently under this package and image version.

The generated plan archive has SHA-256
`387408f6d2c55e6ae4d61573b46bc18b5f6581eec0be2cb17a71f35c9dce01e7`.
It is extracted and validated by `stage_plan.sbatch` inside an Ada CPU
allocation, leaving the HPC head node to handle only a small file transfer
and scheduler submission. The plan manifest SHA-256 is
`39f601c57292ed4316993683cc07a8b8484ca25be9b0dc13193830cf7fc1e5c3`.

The generated six wave scripts request twelve hours by default. Submit
bounded case ranges with measured time overrides to fit queue availability;
do not treat a pending or completed job as scientific acceptance. Independently
audit each terminal case and preserve failures. Do not run file-backed or
SSD-streaming science on UCT HPC.

Compute-node staging job `1605327` completed `0:0` and verified the archive,
462 distinct resident-only cases, source identities and six wave scripts.
Six bounded COIL20 arrays (`1605329` through `1605334`) then completed all
42 cases. The versioned small-manifest auditor at
`/scratch/firenze/NN/benchmarks/audit_matched_77b852f_20261106_v1`
(source SHA-256
`ae9ba4cf0087474de43168b4161739d2075f053562438248976e555da0492a8c`)
accepted all 42 with fresh terminal Slurm accounting. An earlier partial
audit saw one scheduler mismatch and an incomplete record while jobs were
still finishing; both resolved on terminal review. The other 420 cases were
not yet run at that audit. This is a qualification slice, not a scaling or
publication result.

The next six bounded Fashion-MNIST arrays (`1605376` through `1605381`)
were submitted for case indices 7–13 with twenty-minute limits. Prior
same-settings four-core Fashion cases completed within roughly three minutes;
these new-source cases still require terminal input, backend, quality,
memory and scheduler audit. Do not duplicate them while queued or running.
