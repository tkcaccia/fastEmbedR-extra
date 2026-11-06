# File-backed landmark PCA projection pilot

Status: CPU and single-CUDA correctness validated on Chiamaka. Metal and
multi-GPU execution remain unvalidated. This candidate is uncommitted and
was not used by the source-locked Mac benchmark.

The isolated package candidate adds `massive_project_pca(fit, x, output,
backend, n.cores, chunk_rows, memory_limit, devices, landmarks, checkpoint,
resume)`. A streamed PCA fit
on a `massive_select_landmarks()` file can now project another file-backed
matrix in bounded chunks. It reuses the existing CPU, CUDA, Metal, and CUDA
row-sharded score writers, returns a file-backed score descriptor, and
records backend, worker, resource, source, model, and output identities.
Supplying the saved landmark selection verifies its source against the fit
and full input, then records the original landmark row IDs.
Backend requests fail explicitly when unavailable. Checkpoints identify the
source, fit, implementation, worker count, chunk size, backend, and requested
CUDA devices. Resumes reject mismatches.

The checkpoint-enabled package archive has SHA256
`c5b116d23dcbd0d6ca7f0ac13f1a11cfa0263bab2e3004b5a6e06598deeaeb77`.
Its `R/massive_pca.R` has SHA256
`2b4f4344c6433335a42b8418f5b36cf5be9ef176be92de66494df1ecabb72570`.
In the R 4.6.1 container on Chiamaka, the original projection tests passed
with ten CPU and four CUDA expectations. Added interruption tests passed
with eight CPU and four CUDA expectations: each stopped after one committed
batch, resumed, and matched a fresh projection. The CPU test also rejected a
changed worker count and changed landmark row IDs. The CUDA test used the RTX
5060 Ti; no GPU compute context remained afterward. The build stayed in an
isolated validation directory and did not modify the deployed image or jobs.

The real-data pilot reused an existing 70,000 x 784 MNIST float32 file,
selected 7,000 random landmarks with seed 42, fit two PCA components on CPU,
then projected all 70,000 rows with one CPU worker, eight CPU workers, and one
CUDA GPU. This pilot used the preceding numerical projection implementation;
the subsequent focused tests verified the added landmark identity checks.
Input and output checksums are in
`benchmarks/linux/pca-landmark-projection-20261102/evidence/`.

| Projection | Maximum absolute error, first 1,000 rows | Relative to maximum score | Result |
| --- | ---: | ---: | --- |
| CPU, 1 worker | 0.0000608 | 3.10e-8 | Pass |
| CPU, 8 workers | 0.0000608 | 3.10e-8 | Pass; full score file byte-identical to 1 worker |
| CUDA, 1 GPU | 0.001024 | 5.22e-7 | Pass |

The independent audit uses tolerance `1e-4 + 1e-6 * maximum absolute
reference score`, which was 0.002062 for this sample. The initial validator
used a fixed 0.001 cutoff, so it exited 1 after all projections completed;
that cutoff was too strict for float32 CUDA accumulation over 784 columns.
The separate audit exited 0 and verified the original input, package, script,
and output checksums. The pilot validates correctness and route selection;
the subsecond projection times are not suitable as performance estimates.

Remaining work: real Metal and multi-GPU tests, including their checkpoint
recovery, and a sufficiently long performance campaign
across datasets. The Mac's source-locked benchmark must finish before its
result audit or new Metal qualification.
