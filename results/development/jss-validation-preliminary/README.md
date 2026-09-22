# Preliminary current-source t-SNE long-run check

This is diagnostic evidence, not the release-locked publication result. It was
generated on 2026-09-21 from the current local fastEmbedR 0.1 source at commit
`09ee7212f22b0502a8b363c190577d6c6aac09b6` with an explicitly recorded dirty
working tree. The fixed 2,000-row MNIST bundle and Python openTSNE reference
layouts are from the earlier matched-input experiment, so the same compact
affinities, initialization, seed, 250 early-exaggeration iterations, and 750
normal iterations were reused.

The historical CPU KL of 1.923 and Metal KL of 1.899 did not reproduce with
the current source. At FFT grid 256, the three CPU common-affinity KL values
were 1.760, 1.763, and 1.756; the Metal values were 1.777, 1.801, and 1.766.
Their median relative differences from the seed-matched Python openTSNE values
were -0.60% and +0.90%, respectively. Grid 128 was also within 2.4% for every
seed. Grid 512 was substantially slower on CPU and did not improve KL over grid
256.

The full release-locked CPU/CUDA/Metal/Python campaign remains necessary. The
scripts in this suite regenerate exact fixed inputs and report independent
long-run checkpoints, grid sensitivity, thread sensitivity, objective values,
quality metrics, and layout agreement without silently changing backend.
