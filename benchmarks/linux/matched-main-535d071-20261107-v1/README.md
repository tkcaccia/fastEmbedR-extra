# Matched resident CPU benchmark: fastEmbedR 535d071

This cohort uses package main commit
`535d071849945db3fa550d3c50f80633b91748cc` and immutable HPC image
SHA-256 `15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2`.
It is separate from all `afeaffc`, `7c68bc2` and `77b852f` results.
The earlier Fashion-MNIST PCA 4/8/16/32-core failures remain preserved in
the `77b852f` cohort; they are not overwritten or pooled here.

The reviewed CPU4 case panel expands to 462 cases: eleven datasets,
PCA, 2D/3D t-SNE, 2D/3D UMAP, Leiden and Louvain, and 1, 2, 4, 8, 16
and 32 requested cores. Every case uses resident input and algorithm
state, one fit per allocation, and no spill. The runner checks exact raw
input SHA-256, shape, requested and observed backend and worker count,
all-row output, quality, stage times and memory. The plan is staged and
audited on CPU compute nodes; no file-backed or SSD-streaming scientific
work is allowed on UCT HPC.

The generated plan archive SHA-256 is
`8d228eaaebec432bbda7da1e5248f357782277699168f7935cdd5584ec7631dd`.
The plan-summary SHA-256 is
`5a6789187a304f76176cc9a9c4d00191aaf4869ba46da854dd1ae302ea0448f9`.
The 462-case manifest SHA-256 is
`641b17df67f700cd8ba5956c4a7bb2867155362f1dab5cb52a66125710013bea`.
Sixteen planner and auditor tests passed locally. The image build job
`1606224` and 32-core resident PCA pilot `1606228` completed `0:0` on
Ada compute nodes; the pilot verified the image digest, embedded source
commit, 32 requested and effective workers and score parity.

The generated array scripts request a twelve-hour upper bound. Submit
small, measured case ranges with shorter limits where appropriate and
independently audit every terminal case. A completed scheduler state alone
does not qualify a manuscript result.

The four corrected Fashion-MNIST PCA cases at 4, 8, 16 and 32 cores were
run as jobs `1606232`–`1606235` and accepted by the compute-node audit
`1606236`. The six COIL20 waves `1606237`, `1606239`, `1606243`,
`1606249`, `1606252` and `1606259` completed. Compute-node audit `1606282`
accepted all 42 COIL20 cases and the four Fashion PCA cases: 46 accepted,
416 still missing from this 462-case plan. The audit records are under
`/scratch/firenze/NN/benchmarks/audit_matched_535d071_20261107_v1`.

The remaining Fashion-MNIST method/dimension cases were submitted as six
one-hour, six-task arrays `1606292`–`1606297` for 1, 2, 4, 8, 16 and 32
cores. They are not accepted until terminal results pass a new independent
compute-node audit. All cases remain resident-only; no file-backed or
SSD-streaming science is run on the HPC.
