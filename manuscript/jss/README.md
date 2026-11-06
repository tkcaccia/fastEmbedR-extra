# JSS manuscript bundle

This directory contains the current editable JSS manuscript and supplement,
their bibliography and JSS style files, the compact generated table inputs,
the figures referenced by the TeX sources, and the built PDF/Word outputs.
Raw benchmark matrices and per-observation coordinate files are not needed
to compile the documents and are not included here.

The TeX, PDF, and DOCX files are an internal planning draft. Its `XXX`
slots are unverified results and must be resolved before submission.
Failed-audit mixed-boundary runtime figures now live in the supplement rather
than the main results section. A separate opt-in reviewer-closure arm is
documented in `benchmarks/linux/jss-review-validation/reviewer_closure/`;
its 100,000-row full-versus-landmark and bounded-RAM Deep1B results remain
unmeasured until their new campaigns pass audit.
The supplement now includes a small, explicitly provisional CPU/CUDA
kill-and-resume pilot; it is not a Deep1B recovery-speed claim. It also
reports the source-locked Deep1B five-million-row HNSW holdout and the
completed paired CUDA candidate run. The paired audit is `WARN` because
one cuML t-SNE fitted KL value is invalid; the extended JSS and Deep1B
components are not yet final publication evidence.

## Build the documents

From the repository root:

```sh
bash manuscript/jss/build.sh
```

The command builds both PDFs and both editable DOCX files under `outputs/`.
Use `bash manuscript/jss/build.sh pdf` to build only the PDFs. The PDF build
requires `latexmk`, a LaTeX installation, and the packages requested by
`jss.cls`. The Word build additionally requires R, Pandoc, Python 3, and
`python-docx`. `LATEXMK`, `RSCRIPT`, `PANDOC`, and `PYTHON` may override the
corresponding executable names.

The manuscript's tables, plots, and gallery are already present in
`generated/` and `figures/`, so the document build does not need the raw
campaign. The scripts that generated these assets are in `analysis/`;
[its README](../../analysis/README.md) gives the campaign-level commands.
The three family runtime figures and the gallery were generated with
`analysis/build_table5_and_embedding_gallery.R`, which uses the campaign
helpers in `benchmarks/linux/jss-review-validation/common/common.R`.
The current diagnostic runtime figures were redrawn from the archived
`generated/table_all_methods_runtime_supp.csv` with
`analysis/render_runtime_from_compact.R`. That compact table retains
medians, not quartiles; the figures therefore show points without intervals.
The diagnostic tables were
generated with `analysis/build_jss_secondary_tables.R`; the scaling,
landmark, clustering, and 3D comparisons used
`analysis/build_secondary_comparisons.R`. The editable Word documents use
`analysis/prepare_jss_docx_source.R`, `analysis/format_jss_docx.py`, and
`analysis/add_runtime_table_to_supp_docx.py`.

The September 30 campaign predates fields required by the current
`build_secondary_comparisons.R`. Its three published secondary tables are
therefore rendered from the archived compact CSV summaries with
`analysis/render_jss_secondary_20260930.R`; `build.sh` runs this step before
compiling. This does not turn the campaign into a passing release audit.

## Evidence identity

Most benchmark-dependent text and tables use diagnostic JSS campaign
`20260930T203319Z`. The new paired-quality table uses campaign
`20261017T091542Z_jssrepair_CCu2_paired`; the Deep1B HNSW table uses
the corrected v2 audit of `20261017T092413Z_deep_holdout_BxFt`.
The illustrative embedding gallery uses campaign
`20260929T210526Z`, as stated in the supplement. The September campaigns did
not pass
their final audits. The older figures and tables are retained as observed
diagnostic evidence, not as release-level performance claims. The newer paired
campaign has a `WARN` audit, and the corrected Deep1B HNSW holdout passes only
its stated mean-recall gate; neither makes the entire paper audit complete.
Extended campaign `20261017T091542Z_jssrepair_CCu2_extended` supplies the
individually passing one-billion-row streamed PCA and 50,000-row flow18
full/landmark observations in the text. Its file-backed audit is not a
campaign pass (18 PASS, 5 FAIL, 21 BLOCKED), and those cases do not establish
a full Deep1B workflow or multi-GPU speedup.
Compact campaign manifests, audits, per-case CSVs, and paired comparison
CSVs are archived under `results/jss_source_locked_20261017/`. Large inputs,
graphs, and layout binaries are not copied into this repository.
Rebuilding the
assets from a new campaign requires rerunning the analysis scripts and
reviewing the resulting manuscript text and audit status; rebuilding the
documents alone does not change the evidence.

`SOURCE_SHA256SUMS` records the hashes of the TeX, bibliography, styles,
generated inputs, and referenced figures in this bundle. It does not cover
the large PDF/DOCX outputs, whose metadata may change between builds.
`OUTPUT_SHA256SUMS` records the four distributed outputs in this snapshot.

The synthetic layout-guided clustering example is reproduced with
`Rscript analysis/layout_merge_showcase.R` from the repository root using
a fastEmbedR build that includes `graph_cluster(layout_merge = ...)`. It
writes a two-panel PDF/PNG and the pair-level decision CSV under
`manuscript/jss/figures/`; it is not a real-data accuracy benchmark.
