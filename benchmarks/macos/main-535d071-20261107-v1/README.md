# Source-locked Mac resident panel, package main 535d071

This panel is a fresh 693-case cohort built from package commit
`535d071849945db3fa550d3c50f80633b91748cc`. It does not reuse or
overwrite the earlier `afeaffc` results. The eleven-dataset, 3-seed design
covers PCA, 2D/3D t-SNE, 2D/3D UMAP, Leiden and Louvain on CPU1, CPU4 and
the Mac's single Metal GPU. It is resident, full-data, and permits no spill.
File-backed, landmarks, other CPU counts and competitors require separate
cohorts. Deep1B is a separate stress test.

The previous panel reached a 16 GiB R vector limit on ImageNet. Its worker
converted every float32 input to double before preprocessing. A versioned
ImageNet Metal PCA diagnostic kept float32, completed on all 1,281,167 rows,
and peaked at about 11.2 GB resident memory. This panel retains float32
input and sets one R process's vector limit to 96 GiB on the Mac's measured
256 GiB RAM. A failure still stops the serial queue after three consecutive
cases; uncertain cleanup, timeout, >1 GiB new swap, or <100 GiB free disk
stops it immediately. Thirty-six large 3D t-SNE cases have a 7,200-second
per-case bound because the earlier 1,800-second limit timed out on mass41.
The longer bound is a measurement window, not a success claim.

`build_panel.py` verifies the old case roster against the dataset inventory
and produces exact new case manifests, queue and plan identity. `preflight.py`
checks every staged case, all eleven input SHA-256 digests, installed source
and native library identities, available storage, and package loading before
launch. The worker verifies input and installed package identity again for
each case. The runner records timing stages, quality, peak RSS, swap, backend
identity and owned-process cleanup. Metal UMAP also records CPU warm and
Metal optimizer epochs, so mixed 2D execution is visible.

Results are valid only after `audit_panel.py` accepts the terminal queue and
all case manifests. Failures and partial results remain in their own
directories. This cohort must not be pooled with the earlier source version
or a differently configured HPC cohort.
