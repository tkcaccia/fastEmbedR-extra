# CPU clustering audit, Deep1B

This isolated suite uses only Slurm `ada` CPU jobs. It never submits a GPU
job or a controller that can submit one. UCT GPU work remains paused.
`smoke.R` tests the pinned image on a 1,000-row CPU fixture before any
Slurm submission.

The 1M `resident` and `file` jobs fit the **same** verified fuzzy graph.
`resident` reads its edges into R memory; `file` scans CSR files from SSD
and maps label state. The `classic` job additionally loads the original
1M-by-96 matrix into RAM and builds its own graph, so its quality is not
a matched-graph comparison. Compare elapsed time and process peak RSS for
the matched fit jobs, and report graph construction separately. Record
output/workspace SSD bytes. Mapped graph pages
may still count toward RSS through the OS page cache.

The independent 100M run uses 50,000 resident landmarks and streams all
100M source rows from the Deep1B float32 file. It is an approximation,
**not** full-graph 100M Leiden/Louvain. Its fitted reference graph uses one
CPU worker; HNSW query and label assignment request 32 CPU workers. It
checkpoints intermediate stages and checks the complete label-file sizes.

The 1M landmark job retains its verified KNN file and a small fit descriptor.
Four dependent vote jobs read **that same file** and labels with 1, 8, 16,
and 32 CPU workers. They write complete label/confidence files and hashes;
the hashes must agree. These jobs measure streamed assignment, not landmark
graph fitting. CPU allocations match the requested worker counts.

The prior 10M full-graph CPU benchmark spent 10,754 seconds in 16-core
KNN but only 801 seconds in one-core Leiden and 367 seconds in one-core
Louvain. With the current sharded HNSW design, 100M full-graph KNN would
need many more shard/query passes and has not been qualified for a 72-hour
CPU job. Do not present the landmark run as a full-graph result.

Image and benchmark-script hashes are recorded per job. The Deep1B input
uses its pinned manifest hash plus live size/mtime; this suite does not
rehash the 358 GiB file for each fit. `disk_samples.tsv` records the
workspace size every minute, and `workspace_peak_bytes.txt` reports its
sampled maximum. The original input file is reported separately, not
counted as newly allocated workspace. Do not remove source datasets or
previous benchmark evidence. The matched-graph fits depend only on `build`;
the 100M job and vote profiles depend only on the 1M landmark pilot. Check
metrics, Slurm exit status, exact-neighbor recall,
hashes, and disk/RSS evidence before using numbers in a manuscript.
Run `Rscript audit.R CAMPAIGN` after the jobs finish. It writes
`cpu_summary.csv` and rejects unequal 1/8/16/32-worker vote outputs.
`audit_recall_100m.R` independently scans the 50,000-landmark reference
for 128 untouched, evenly spaced 100M query rows; its ID recall is a
sample estimate, not a guarantee for every row.
`submit_scale10m.sh` sends five independent CPU-only landmark jobs at
1, 4, 8, 16, and 32 cores on the same 10M-row window. It records full
elapsed time, HNSW build/query time, label time, effective settings,
external peak RSS, and output hashes. This is a separate scaling campaign;
it does not alter or block the 100M feasibility run.
