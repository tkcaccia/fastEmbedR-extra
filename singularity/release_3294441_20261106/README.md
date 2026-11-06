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

The staged inputs occupied 2.4 MB. Build job `1602864` completed `0:0`
on Ada after CUDA compilation and Singularity's package tests. It created
`/scratch/firenze/NN/singularity/release_3294441_20261106/fastembedr_3294441_20261106.sif`.
The build allocation calculated SHA-256
`46ab05e72da249505e29f833c7f7117c4454e31b7780a4a8f3294c4ee74394c7`
on the completed `.partial.sif` immediately before the no-clobber move to
that final path. The image is read-only. Its saved labels show the exact
package commit, source archive hash, dependency commits and base image.

The CPU-only package build and six focused routing test blocks passed
in job `1602428` after an initial test-harness failure was corrected.
The image compiled the changed CUDA worker for a bounded resident L40S
device pilot with source, device, quality and cleanup checks. It must not
be used for a manuscript result until
that pilot passes. UCT HPC never runs file-backed or SSD-streaming
scientific work.

The staged two-L40S pilot uses a 120-vertex resident four-clique graph,
compares one coordinated CUDA Leiden fit against CPU labels and modularity,
and checks both device identities and nonempty per-device work. Its
launcher verifies the image digest on its GPU compute node and enforces
bounded monitoring, shutdown and owned-context cleanup. Twelve local
synthetic lifecycle and GPU-index-mapping checks passed. Submit this
pilot was held until job `1602864` finished and its image/source identity
was audited. Pilot `1603170` was then submitted and was pending for
Priority at the first check. It has no result yet; preserve any failure
before a versioned retry.
