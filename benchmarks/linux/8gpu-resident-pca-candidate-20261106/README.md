# Resident CUDA PCA beyond four devices: isolated candidate

Package candidate commit `55e3ddf` is local to
`in-progress/fastembedr-8gpu-resident-cluster-20261106`; it has **not**
been pushed to fastEmbedR main or used in a published benchmark. It
follows the independently staged file-backed multi-CPU clustering changes
at `34ad265` and `7852822`, so any later image built from it must identify
all three candidate commits.

Resident PCA already divides covariance and score projection into one row
shard per requested CUDA device. The candidate removes the unrelated
four-device checks in R and C++ while retaining distinct, available
device validation and the requirement for at least two devices. The
small eigendecomposition remains on the CPU, as documented. The source
help and reference topic were updated, and a mocked eight-device public
API routing test was added.

Local R parsing, Linux C++17 syntax checking, `git diff --check`, and an
isolated eight-device R routing check passed. The package's full test file
could not run on this PC because its local R 4.5 library lacks faissR and
the package requires R 4.6; no device result is claimed. The reference
topic was edited to match the roxygen source after local regeneration
failed for the same missing dependency. Regenerate and review it with an
R 4.6 package build before release.

Qualify on real multi-GPU hardware with source identity, eight distinct
device UUIDs, nonzero work on each GPU, CPU reference covariance and score
agreement, finite all-row output, peak host/GPU memory, timing, and owned
context cleanup. The queued Hugging Face eight-A100 clustering job uses a
different, earlier source archive; it cannot qualify this PCA change.
