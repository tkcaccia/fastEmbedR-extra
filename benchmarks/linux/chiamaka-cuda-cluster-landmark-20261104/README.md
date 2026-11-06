# Chiamaka CUDA resident landmark-clustering device check

At 08:10 UTC on 4 November 2026, the isolated candidate installed in
`/tmp/fastembedr_cuda_candidate_20261104/library` passed a 160-row,
five-feature Leiden landmark-clustering probe on Chiamaka's RTX 5060 Ti.
The installed candidate library SHA-256 was
`8a5d24639cb7a000cfc9bc1b653b6c3567e835fdf5bc0fcbed248483c19fea17`.
The selected 80 reference rows kept their fitted labels; all 160 rows
received positive memberships and finite confidence. The result contained
four communities, minimum confidence 0.5003957, and reported CUDA for
the reference fit and query KNN. Graph assembly and label voting were
explicitly reported as CPU work. The fit took 0.338 seconds; this is a
device smoke test, not a speed comparison.

The runner checked input SHA-256 hashes, the expected physical GPU UUID
`GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5`, 13 idle samples across
two minutes, absence of Bora processes, free compute contexts, and low
GPU memory use before launch. It imposed a five-minute test timeout.
The owned R process exited zero, and all three post-test GPU-context
checks were empty. No Bora process was stopped or altered.

The exact runner, R script, synthetic input, and copied
`gpu_probe_evidence_v2/` folder are retained here. The input script and
matrix SHA-256 values are
`21f0ba4bb166b0a34a4658b24e840312d42ebb5178c07d21d83d010163b2d016`
and `dbb0a7286537a0198c51ed9c04d5cdb3326c17217b1037e236635ebe1b406ddc`.
The result SHA-256 is
`5c56c12315adfb9253da3c358e48c4b203842fe7b73d2a458024035590142902`.

This does not establish quality on named datasets, multi-GPU landmark
clustering, or scalability. UCT HPC was not used.
