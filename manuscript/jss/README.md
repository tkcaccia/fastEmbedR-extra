# JSS manuscript bundle

This directory contains the current editable JSS manuscript and supplement,
their bibliography and JSS style files, the compact generated table inputs,
the figures referenced by the TeX sources, and the built PDF/Word outputs.
Raw benchmark matrices and per-observation coordinate files are not needed
to compile the documents and are not included here.

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

The benchmark-dependent text and tables use diagnostic JSS campaign
`20260930T203319Z`. The illustrative embedding gallery uses campaign
`20260929T210526Z`, as stated in the supplement. The campaigns did not pass
their final audits. The figures and tables are retained as observed
diagnostic evidence, not as release-level performance claims. Rebuilding the
assets from a new campaign requires rerunning the analysis scripts and
reviewing the resulting manuscript text and audit status; rebuilding the
documents alone does not change the evidence.

`SOURCE_SHA256SUMS` records the hashes of the TeX, bibliography, styles,
generated inputs, and referenced figures in this bundle. It does not cover
the large PDF/DOCX outputs, whose metadata may change between builds.
`OUTPUT_SHA256SUMS` records the four distributed outputs in this snapshot.
