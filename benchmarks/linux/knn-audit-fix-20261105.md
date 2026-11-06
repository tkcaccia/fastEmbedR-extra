# Deep1B exact KNN audit read-buffer fix (2026-11-05)

The isolated package candidate now caps only `massive_full_knn_audit()`'s exact-reference read block. The cap is `floor(192000000 / (4 * ncol))` rows, further limited by the existing `reference_chunk_rows` setting. At Deep1B's 96 float32 columns this is 500,000 rows (192 MB), below the unchanged native 256,000,000-byte guard. The HNSW shard setting remains one million rows in Silvano's 1M run. The audit still selects the same 128 query rows, scans all one million reference rows, and applies the unchanged 0.99 recall criterion. The effective audit read size is recorded as `audit_reference_chunk_rows`.

Changed package files: `R/massive_knn.R`, `tests/testthat/test-massive-graph.R`, and new `tests/testthat/test-massive-audit-reference-chunk.R` in the isolated candidate. The C++ guard and benchmark runner were not changed.

Verification: an isolated R 4.6 Metal-capable package build passed on Silvano's Mac in `/Users/silvanopiazza/Documents/Stefano/fastEmbedR-knn-audit-20261105`; the focused test file passed 10 expectations, including 128 unchanged audit queries, one-million-row reference descriptor, 500,000-row exact blocks, original one-million-row HNSW setting, and native exact-neighbor/distance parity when the read block changes from 37 to 7 rows. Package source style and diff whitespace checks passed locally.

The Deep1B million-row recall itself has not been rerun. Silvano's Linux/Spark runner must use a newly built package/image containing this source before rerunning; an old source-locked image will still fail the native preflight check. No HPC file-backed scientific job was submitted for this fix.
