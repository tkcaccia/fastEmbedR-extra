# Mac-matched resident CUDA candidate

This candidate is separate from the held raw-input job 1594628. It has not
been deployed or submitted. Its COIL20 2D UMAP case requests two L40S GPUs
and package main `afeaffc39a607c00db5899c284451c6cdbf741bb`.

The worker checks the input SHA256 on a compute node, converts the resident
input to double, fits rank-30 CPU PCA, and uses the scores for CUDA UMAP.
The rank, neighbor count and 600-row quality sample match the running Mac
panel. It records stage times, trustworthiness, label accuracy, output shape,
reported CUDA devices and peak memory on each assigned GPU. Its admission
rejects file-backed data and algorithm state before the fit.

Local syntax and contract tests are preliminary. This candidate needs a
new source-locked deployment, a two-L40S device test, quality review and
terminal cleanup audit. Do not submit it until the earlier new-image pilot
1592858 and held raw-input COIL20 case 1594628 have passed their required
audits. Do not mix results from the raw-input and Mac-matched cohorts.
