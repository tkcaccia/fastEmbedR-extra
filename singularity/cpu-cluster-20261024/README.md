# CPU clustering candidate

Build a new candidate from the pinned CPU32 image and the clean fastEmbedR
commit recorded in `release_inputs/source-identity.txt`. The definition
installs only fastEmbedR; the base image already contains faissR 0.1 and
gpuinfo 0.2.0. Verify the source tarball, base SIF, output SIF, installed
package versions, and shared-library linkage before copying to UCT.

This image is for **CPU-only** `ada` validation. It does not replace the
stable SIF or qualify UCT GPU use, which remains paused.

Pinned base SIF SHA256:
`dd9ed112c638b53f06d7baed51a17de515fa7d58d730c8352fa6fd732ffd265a`.
Build the ignored source archive from the published package commit with
`git archive --format=tar.gz --prefix=fastEmbedR/` and verify it against
`release_inputs/SHA256SUMS` before building. The resulting CPU-clustering
candidate SIF SHA256 is
`5ce92891f6543169078977be5f995fb475d5825c16eee3d035f5829083b6953b`.
`CPUClusterCommit` is the current source label. The inherited
`FastEmbedRCommit` label describes the base image, not the reinstalled
package; inspect `cluster-source-identity.txt` for the full provenance.
