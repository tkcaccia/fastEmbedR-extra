# Mac panel continuation v6

The Mac source is
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031/panel-v6`.
The active queue is `panel_v6_20261102`. It reuses the completed,
source-locked COIL20 and MetRef runs from `panel_v5b_20261102` and the
completed 147-arm USPS run with its separate versioned quality re-audit
in `results/recovery/USPS_quality_v2`. No original result was overwritten.
The remaining eight datasets run serially. A source hash lock and
per-dataset input, execution, saved-layout, quality, recall, and disk
checks gate the queue. The selector accepts a mix of reused and new
run IDs and records the exact audit directory for each dataset.

USPS originally stopped in its quality audit because no CPU thread
setting qualified for full fuzzy UMAP. Audit v2 selects the fastest CPU
setting only for descriptive timing, records that the baseline is
unqualified, and disallows a qualified Metal speed claim for that
method. The revised audit passed on the preserved USPS layouts.

The Deep1B 100M v3 queue waits for this panel's exit code zero and
selector output. The old Deep1B v1/v2 controllers exited before any
100M calculation because the prior panel stopped. Preserve their logs.
