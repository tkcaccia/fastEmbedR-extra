# Deep1B 100M Mac queue v3

The active controller on Silvano's Mac is
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031/deep1b-100m-v3/benchmark/run_deep1b_mod10_100m_queue_v3.sh`.
It waits for the audited `panel_v6_20261102` queue and its selector.
It uses the verified 100,000,000-row Deep1B subset with SHA-256
`259e5ed58e0218790bec8e8514c011f39bfd839c012d8d818d9106773ffeac94`.
The original one-billion-row source was removed after independent
verification; its retirement evidence remains in `deep1b-100m-v1`.

This version converts full KNN distances to directed UMAP memberships
before global fuzzy-graph sorting. Its serial stages cover preliminary
full-graph execution, CPU and Metal PCA, full 30-neighbor CPU HNSW,
t-SNE affinities and 750 CPU optimization iterations, UMAP membership
and fuzzy graph construction, Metal and CPU UMAP fits, and CPU Leiden.
The stage guard and 200 GiB free-space reserve stop on resource failure.
The script never retries or restarts the Mac. Preserve every stage's
outputs and logs before making a versioned correction.

Static source-based admission estimate for 100M x 96 and k=30:
the HNSW resource formula gives about 83.5 GiB peak resident memory for
25M-row shards; KNN plus directed memberships need about 33.5 GiB of
output; both symmetric graphs together are bounded by about 90.9 GiB;
nine 2D layouts need about 6.7 GiB. The global graph sort's temporary
admission is about 53.8 GiB per sort. These are upper-bound estimates,
not measured usage. The Mac had about 424 GiB free before the 100M queue
started, and the queue's 200 GiB free-space reserve remains the live gate.
The checkpointed HNSW stage builds each shard with one effective CPU
worker, then queries with the requested 20 workers; it stores metadata
and partial KNN output, not a duplicate on-disk HNSW index. Report the
build and query phases separately.

After a successful queue exit, run the separately staged
`postprocess/audit_deep1b_100m_mac_v1.py` on the Mac with the v3 run
directory as its argument. It independently hashes the subset, package,
locked scripts, and stage files; checks every saved layout coordinate;
and scans both full CSR offset arrays. The separate
`analysis/audit_deep1b_100m_graphs_v1.R` reopens both graph manifests,
checks result descriptors, and records the 32-row strict KNN recall audit.
The `analysis/run_deep1b_100m_postprocess_v1.sh` watcher runs those two
checks in order only after queue success and records its own exit marker.
An observed recall below 0.99 is reported as a quality failure even if
the structural audit passes. Do not treat a queue exit alone as the final
manuscript audit.

The independent `analysis/run_deep1b_100m_report_v1.sh` watcher creates
the 15-stage CSV and TeX supplement only when both audits have passed.
The 11-dataset panel has a separate supplement watcher. These reports
show measured stage timings and quality flags; they do not infer an
end-to-end speed advantage from unrelated stages.

The separate layout-quality watcher reads 4,096 deterministic query rows
from the completed 30-neighbor graph. For each of six full 2D layouts,
it reports how often a stored neighbor is closer than a deterministic
vertex outside that row's stored top-30 list. The formula generates
query and negative IDs without saving an index. This is a descriptive
diagnostic, not whole-graph trustworthiness or a method-quality gate.
The installed-identity watcher also rehashes the R package's loaded
`fastEmbedR.so` after the structural audit and compares it with the
binary hash recorded at installation.
