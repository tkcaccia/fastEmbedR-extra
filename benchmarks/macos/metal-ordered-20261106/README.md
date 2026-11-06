# Ordered Metal UMAP diagnostic, 2026-11-06

Status: source staged, **not compiled or tested on a Metal device**.
The source-locked Mac benchmark panel is still running; do not run
this calculation concurrently or alter the panel's package library.

The isolated package candidate `1846203` builds on package main
`7c68bc2`. Its source patch is preserved at
`development/candidates/fastEmbedR-metal-ordered-7c68bc2-to-1846203.patch.gz`.
The uncompressed patch SHA-256 is
`c3f5af2e0c4eadbd077b3ac06ffc3d8a0159a65afbc3cabeb4003b879d7f94cb`;
the compressed file SHA-256 is
`5cb85f161c4f2c0756797191744b73cfa38559f76a767b4a5310309720301dc2`.
It replays byte-for-byte onto the base source. The R check script SHA-256
is `5a94093e3f6a01f7755c5274cac6f69057bba6d8491d0bc87ff2dae262a75e3e`.
The staged package archive SHA-256 is
`9032793bf88a72a623fe0a95ccf48bcb745df9dbc2d1b2395d4b1aeda280e466`.
`build_candidate.sh` checks that archive before installing to its own
library under Stefano; it has not been run yet.

The candidate adds an internal diagnostic sampler mode that processes
small groups of rows in order while preserving parallel work within each
group. `FASTEMBEDR_METAL_UMAP_ORDERED_ROWS` selects a group size from 1 to
4096 (default 64). It supports only 2D at this stage. Existing sampler
modes retain their call pattern, with an explicit zero row offset for the
shared 2D kernel. This is a hypothesis about the Fashion quality gap,
not a fix yet.

After the active panel finishes, build the candidate in a new library
under `/Users/silvanopiazza/Documents/Stefano`. Run `check_ordered.R`
first on 300 Fashion rows and one seed, then on the fixed 5,000-row
30-neighbor Fashion graph and seeds 4, 17, 42 for several group sizes.
The script compares the same initialization and graph against the CPU
clean-atomic optimizer at 400 epochs and records silhouette, elapsed
time, finite all-row output and the actual Metal optimizer identity.
The established gate is Metal silhouette at least CPU minus 0.01 on
every seed. Require repeatability, another dataset, 3D coverage and a
speed check before integration or any manuscript claim. Preserve
failures and run each revision under a new source identity.
