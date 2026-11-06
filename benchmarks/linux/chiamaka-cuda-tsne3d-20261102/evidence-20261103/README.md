# Chiamaka CUDA 3D landmark qualification, 3 November 2026

Device: NVIDIA GeForce RTX 5060 Ti, UUID `GPU-59b2b884-a1c9-f7a3-9f35-e8380f4609d5`.
The test used the existing 29 October Singularity image, the source archive SHA256
`5d0bee0b0951c07d0d3b504c17716016938d401dd23ce35739b8652a613c48c0`,
and the isolated installed library SHA256
`c0d50292330cad4cd835394e5889b8b806e79d458d9b0beaecd2757421ef2839`.
The queue verified all source, image, library, and test-script hashes before GPU admission.

The first queue stopped before calculation because a multiline `Rscript -e`
expression contained a literal backslash. The second queue passed 3D t-SNE
but its 3D UMAP assertion rejected differing R matrix attributes. A direct
diagnostic measured exactly zero coordinate difference at all 23 landmarks
in both fuzzy and binary modes. The package candidate's assertion was
corrected to compare coordinates while ignoring attributes.

The final queue (`run_when_idle_v4.sh`, SHA256
`4860f1e7d58a7b7ef100986edf588a1713d68430f428ade9b08460e76ef414ae`)
required an idle GPU and no Bora process for 30 seconds, rechecked idle
before each case, limited each case to 120 seconds, and checked that owned
processes and GPU contexts ended. It finished at 2026-11-03 06:48:07 UTC with
`QUEUE_EXIT status=0` and `ALL_3D_DEVICE_TESTS_PASSED`. The queue PID was
absent and `nvidia-smi` reported no compute context afterward.

| Case | Result |
| --- | --- |
| 3D CUDA landmark t-SNE and held-out model projection | Passed |
| 3D CUDA landmark UMAP, fuzzy and binary graphs, fixed landmarks and held-out model projection | Passed; 23 landmarks, 45 rows, nonzero third axis |
| 2D CUDA landmark t-SNE | Passed |
| 2D CUDA landmark UMAP and 2D t-SNE regression | Passed |

The `v4-*.log`, `umap3d_v4.csv`, and `umap2d_v4.csv` files hold the device
results. `queue_v2.log` and `diagnose-umap3d.log` retain the failed assertion
and its numerical diagnosis. This is a small correctness test, not a speed
benchmark or a multi-GPU qualification.
