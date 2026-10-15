# File-backed opening phase

The complete JSS campaign starts this phase immediately after comparator input
preparation, alongside the ordinary CPU/CUDA benchmark lanes. `cases.csv` is
the complete case registry. Each case writes `result.csv`; `audit.py` writes
`summary.csv`, `paired_comparisons.csv`, and `audit.txt`. The final campaign
audit rejects FAIL, BLOCKED, TIMEOUT, or MISSING cases. Workers continue after
individual failures so all cases have an explicit status.

1. **Matched correctness:** mass41, flow18, FlowRepository, and ImageNet.
   Fixed 1,024-row samples are saved as row identifiers; streamed exact KNN is
   compared with dense Euclidean distance, and streamed PCA score distances
   with `stats::prcomp`. Gates: recall >= 0.99, PCA distance correlation >=
   0.95. Full file-backed and resident UMAP/t-SNE are also fitted on those
   rows; Preserve@30 may not fall more than 0.10 below the resident route.
   This does not validate all rows of the source datasets.
2. **Real-data scaling:** Turing-ANNS and DEEP prefixes of 100,000,
   1 million, and 10 million rows each.
   File-backed CUDA PCA, full sharded CUDA IVF KNN, and landmark UMAP/t-SNE
   have separate timings, process peak RSS, backend checks, and saved output.
   These are prefix experiments, not 1-billion-row fits.
3. **Memory boundary:** streamed CPU PCA on each complete 1-billion-row file.
   The input must exceed the effective Slurm/cgroup memory budget, and process
   peak RSS must remain below it. The physical and effective limits are saved.
   Cache use and filesystem traffic are not process RSS.
4. **Full versus landmark:** on the same first 50,000 flow18 rows, run full
   disk-backed KNN/graph/PCA/optimization and landmark embedding with 5,000
   landmarks. Compare time, RSS, output bytes, and Preserve@30 on identical
   fixed 256-row evaluation samples. The full route is not an R matrix fit.
5. **Multi-GPU:** first 100,000 Turing rows, one versus two CUDA devices in
   the same 2-GPU Slurm allocation for PCA, landmark KNN, UMAP, and t-SNE.
   Returned device metadata must match the requested IDs. Chiamaka has only
   one GPU, so two-GPU cases require HPC validation.
6. **Recovery:** a separate CPU or CUDA worker process is killed with SIGKILL
   after writing a covariance checkpoint. The parent process resumes and is
   compared with a fresh fit. This tests process death, not node failure or
   power loss.

BigANN files are read from `$BIGANN_DATA_ROOT`, defaulting to
`/scratch/firenze/NN/Data/BigANN`. The full downloads and manifests must be
present; no generated or substituted input is accepted. The installed package
version and DLL SHA-256 are checked before a case runs. GPU identity comes
from returned native metadata, not from requested arguments alone.

`peak_rss_bytes` is the R process high-water mark from `/proc/self/status`.
It is not GPU VRAM or total filesystem cache. CPU/GPU peak values should not
be conflated. The case runner saves raw disk-backed outputs under the campaign
results directory; copy only summaries and needed plots for manuscript work.
