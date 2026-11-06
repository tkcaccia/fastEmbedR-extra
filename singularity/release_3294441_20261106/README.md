# Candidate CUDA image for resident clustering device scaling

Package source is fastEmbedR main commit
`32944414d8256da04d67df2ab8a62131ba61028c`. It extends the
resident `graph_cluster()` route beyond four visible CUDA devices.
The source archive was built with `R CMD build --no-build-vignettes
--no-manual` from that clean commit; its SHA-256 is
`bbca72443836f3d2ef004c0722f5e6594791a5a3e7dbc56e8d0de9dc2e05f8d5`.
The source manifest retains the previously qualified faissR and gpuinfo
commits and archives. The build script checks all three source archives
and the base-image digest **inside its Ada compute allocation**, then
builds an immutable SIF. It records the final SIF digest there; never
hash the large image on the HPC head node.

The staged inputs occupied 2.4 MB. Build job `1602864` was submitted to
the Ada CPU partition. Its terminal build result, image hash, and CUDA
compilation evidence must be audited before a GPU pilot is queued.

The CPU-only package build and six focused routing test blocks passed
in job `1602428` after an initial test-harness failure was corrected.
This image is needed to compile the changed CUDA worker and then run a
bounded resident L40S device pilot with source, device, quality, memory
and cleanup checks. It must not be used for a manuscript result until
that pilot passes. UCT HPC never runs file-backed or SSD-streaming
scientific work.
