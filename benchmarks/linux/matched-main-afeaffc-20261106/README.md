# Matched-settings Mac/HPC resident cohort

This versioned HPC worker uses the same scientific settings as the running
Mac CPU/Metal panel: float32 input digests verified in HPC job 1592295,
CPU rank-30 (or input-width-minus-one) PCA preprocessing for UMAP/t-SNE/
clustering, 30 neighbors, t-SNE perplexity 30 with 300 normal iterations,
and the same seed and 600-row quality sample. PCA fits original features.
Preprocessing, graph construction, target-method fit, quality and writing
are timed separately. All inputs and algorithm state remain resident in
memory. File-backed input and GPU exposure are rejected before execution.

The new-image COIL20 four-core 2D UMAP pilot 1593561 completed. It reported
rank 30, fit 0.339 s, trustworthiness 0.9735 and label accuracy 0.8917.
The corresponding Mac source-locked four-core case reported fit 0.153 s,
trustworthiness 0.9755 and accuracy 0.8917. These single-run observations
qualify the matched route; they are not publication speed estimates.

Array 1593945 contains the remaining 21 two- and three-dimensional UMAP
cases at four cores across all 11 datasets, throttled to one active case.
`cases.jsonl` records the exact pilot and array plans. Four COIL20 method pilots in array 1593960 completed for PCA, t-SNE,
Leiden and Louvain. The matched 21-case 2D/3D t-SNE wave 1594037 was
accepted. The remaining 30-case PCA/Leiden/Louvain wave is staged, but its
first submission hit `AssocMaxSubmitJobLimit`; it must wait for quota.
All 77 seed-4, four-core matched cases are in `cases.jsonl`. Other seeds,
core counts and GPU backends still need matched cohorts. The earlier
HPC raw-input waves remain separate development evidence and must not be
combined with this cohort in the manuscript.
