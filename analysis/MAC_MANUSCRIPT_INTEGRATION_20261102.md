# Mac results integration after the source-locked campaign

On 2 November the user postponed the real Deep1B 100M run until after
the missing algorithms are implemented. The v3 queue was terminated
while waiting: `deep1b-100m-v3/queue100m/status.csv` has only its header,
`queue.exit` is nonzero, and no 100M calculation stage started. The
joint `final-audit-controller/final_audit.exit` is consequently nonzero
by design. The live 11-dataset panel continues unchanged. Report its
results after its own audits; use a new, source-locked 100M campaign
after implementation rather than retrying v3. The Mac retirement and
subset manifests are preserved under Stefano.

The current main paper's Apple Metal subsection reports a different
8 GB Apple M3 experiment. Preserve those observations and identify the
new 256 GiB M3 Ultra campaign separately. Do not merge their speedup
statistics or change the old subsection before the new audit finishes.

The Deep1B supplement currently describes an HPC source-row window and
reserved one- and ten-million-row cases. The new Mac experiment uses
every tenth one-based source row (`i %% 10 == 0`) for exactly 100M rows,
30 neighbors, and full-row fits without landmarks. Add a distinct Mac
subsection after the existing Deep1B account; do not fill the old HPC
placeholders with Mac measurements.

The preserved Mac subset manifest records 100,000,000 rows, 96 columns,
little-endian float32 FBIN, and 38,400,000,008 bytes. It records the
source SHA-256 as
`1178bb266619c2d7882795861772b50cb0e2bf111a3b786a188aa3ea6137c7c4`
and subset SHA-256 as
`259e5ed58e0218790bec8e8514c011f39bfd839c012d8d818d9106773ffeac94`.
The retirement record states that the full 1B source was removed after
subset verification, as authorized by the user. The future 100M queue
must independently recheck the subset hash before its first stage.

Required evidence before inserting the 11-dataset Mac panel:

1. `panel_v6_20261102.launch.exit` is zero and its selector has 44
   audited full-pipeline observations across all 11 datasets.
2. `panel-v6/postprocess/supplement.exit` is zero and the 77-row CSV
   and TeX table have valid SHA-256 records.
3. `panel-v6/postprocess/cpu_scaling.exit` is zero and the 462-row CPU
   grid and 42-row scaling summary have valid SHA-256 records.
4. Run the separately staged `analysis/audit_mac_panel_only_v1.py` under
   Stefano. Its `panel-only-audit-v1/audit.json` must report
   `panel_evidence_verified`, rechecking the panel source lock, selector,
   report hashes, all 11 audits, and positive Metal allocations.

At 21:05:48 UTC on 2 November, the separate panel-only audit waiter started
on the Mac as PID 20955. Its source is
`analysis/run_mac_panel_only_audit_after_completion_v1.sh`, SHA256
`d0a94ff25dcf7eb6ebdedd2de1f47bb7cd14287a896022dc2813a551f66ee98f`.
The audit script under Stefano matched local SHA256
`56ce08bd060f83b2d294b07a6c8b0a9ff3b89633bac64408c5696a7d948e7345`.
The waiter makes a locked audit-script copy, then sleeps until the panel
and both report builders have zero exit markers. At 22:05:56 CET it was
live alongside the three source-locked controllers, and no panel-only
audit had started. It expires after seven days if prerequisites remain
incomplete. Its log is `analysis/panel_only_wait.log` under Stefano.
The intended `panel-only-audit-v1` result path initially held only a
checksum-identical copy of the audit script. That directory was renamed
to `panel-only-audit-v1-staged-source-20261102`, preserving its content,
so the future audit can create its result directory without collision.

The later Deep1B subsection requires a new versioned queue with the
new implementation, complete source and installed-binary identity,
successful stage and guard reports, independent byte/graph/layout
audits, and verified report hashes. The old v3 queue and joint final
audit cannot qualify that new run.

Copy the small final CSV and TeX outputs into the isolated companion
checkout under `manuscript/jss/generated/mac/`, rehash them, and include
them from the supplement. State all descriptive timing and quality flags;
claim a Metal speed advantage only for rows that meet the stated quality,
CPU baseline, recall, and speed gates. For the future 100M run, state the
actual exact-reference recall and layout-diagnostic sample sizes; neither
is a whole-graph quality guarantee.

The postponed v3 HNSW design requested 20 CPU workers for queries, but
its checkpointed index construction forced one build worker. Reassess
that limitation in the new implementation and report build and query
times and effective worker counts separately.

## Interim audited panel observation: MNIST

The source-locked `panel_v6_20261102_MNIST` run completed all 147 arms.
Its execution audit reported no issues and its separate saved-layout,
quality, and paired-speed audit completed. All 21 Metal arms report
`actual_backend=metal` and positive observed Metal allocations in
`benchmark_runs.csv`. The seven-row `quality_speed_summary.csv` reports
a recall-qualified end-to-end
CPU-to-Metal median ratio of 1.35 for PCA. Full-pipeline t-SNE has a
5.76 paired quality-and-speed ratio, but its sampled exact-neighbor
recall fails, so it is not a recall-qualified end-to-end claim. The
three Metal full-t-SNE recall records all fail the sampled gate: their
mean recall is 0.99323 and minimum sampled-row recall is 0.80,
versus a minimum of 0.96667 among the 18 CPU records. The 16.60 ratio
for t-SNE from precomputed KNN describes only that embedding stage.
All four UMAP method summaries fail the paired quality gate despite
descriptive ratios above one. Each failed UMAP seed pair has a silhouette
decrement
below the allowed -0.01 threshold; some pairs also miss the KNN
preservation threshold. Preserve these failures in the final per-dataset
table. This is an interim observation, not an 11-dataset result.

## Interim audited panel observation: FashionMNIST

The source-locked `panel_v6_20261102_FashionMNIST` run completed all
147 arms and both audits. All 21 Metal arms report the Metal backend and
positive observed allocations. The seven-row quality summary qualifies
end-to-end CPU-to-Metal median ratios of 1.35 for PCA, 2.94 for full
t-SNE, and 5.00 for full binary UMAP. The 15.84 ratio for t-SNE from
precomputed KNN is an embedding-stage result. The remaining three UMAP
routes fail the all-seed paired quality gate; their ratios of 2.29,
7.38, and 24.42 are descriptive. Preserve every failed gate in the
final table rather than generalizing the qualifying binary UMAP result.

## Interim audited panel observation: TabulaMuris

The source-locked `panel_v6_20261102_TabulaMuris` run completed all
147 arms and both audits. All 21 Metal arms report the Metal backend and
positive observed allocations. PCA has a recall-qualified end-to-end
CPU-to-Metal median ratio of 2.23. Fuzzy full UMAP passes the paired
layout and speed gates with a descriptive ratio of 5.67, but its sampled
exact-neighbor recall fails; it is not a recall-qualified end-to-end
claim. t-SNE from precomputed KNN passes its paired quality and speed
gates with a 15.83 ratio for the embedding stage only. The remaining
four method summaries fail paired quality, with full t-SNE and full
binary UMAP also having failed sampled recall. Preserve the method-level
gates in the final per-dataset report.

## FlowRepository timing quarantine

The panel process group was stopped for hours and resumed on
2026-11-03. The FlowRepository CPU binary-UMAP 12-thread seed-4 arm
finished at 21:18:43 with a recorded total of 39,997 seconds.
That wall time includes the stopped interval and must be excluded
from timing, speedup, and efficiency summaries. The active queue
and its files remain untouched. After the panel completes, run
this arm in a new versioned recovery directory and audit its
backend, quality, memory, and elapsed time before inclusion.
