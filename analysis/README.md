# Analysis workflow

The analysis has two stages.

1. `aggregate_linux_results.R` and `aggregate_macos_results.R` read local raw
   result archives and write compact CSV summaries.
2. `build_tables.R` and `build_figures.R` use only those aggregate CSV files.

This separation allows all publication tables and figures to be rebuilt
without distributing restricted datasets or multi-gigabyte worker outputs.

The JSS campaign writes an `embedding.csv.gz` for each successful PCA, t-SNE,
and UMAP method. Build the merged R/Python runtime table, peak-memory
table, three family runtime figures, and method gallery from one campaign:

```bash
Rscript analysis/build_table5_and_embedding_gallery.R \
  /absolute/path/to/campaign/results \
  /absolute/path/to/output/generated \
  /absolute/path/to/output/figures/embedding_all_methods \
  figures/embedding_all_methods
```

For a lightweight local copy without coordinate tables, append
`--runtime-only` to build the table and runtime figures from aggregate data.
Build the gallery on the HPC before transferring rendered plots. The reader
also accepts older uncompressed `embedding.csv` files.

Build the diagnostic CUDA quality, PCA accuracy, and clustering tables
from the same campaign:

```bash
Rscript analysis/build_jss_secondary_tables.R \
  /absolute/path/to/campaign \
  /absolute/path/to/output/generated
```

To browse every saved diagnostic and comparator PNG from one campaign,
generate a local HTML index. It links to the existing files without copying
or modifying campaign evidence:

```bash
python3 analysis/build_campaign_plot_gallery.py \
  /absolute/path/to/campaign \
  /absolute/path/to/plot_gallery.html
```

The UMAP table and figures include separate fastEmbedR fuzzy and binary
routes; binary is an adjacency-only sensitivity analysis, not standard UMAP.

`stats::prcomp()` is not a timed PCA comparator. Dense SVD is used only
as an untimed numerical reference in PCA validation.

The second and third paths are output directories. The fourth argument is the
figure path relative to the LaTeX document. Omit them to write under the
campaign's `results/publication` directory. The builder reads only
`aggregate/workflow_comparators_all.csv` and coordinate CSVs inside the
specified campaign. The table and figures combine successful R public calls
and direct-Python fits, with distinct timing-scope markers and table columns.
Completed single fits are marked separately from repeated timings. Failed
or missing combinations retain explicit status codes and never appear as
completed plot points, even if a failed worker wrote an elapsed time.
Cross-scope speedup claims are not supported.
`peak_memory_by_dataset.csv` and `peak_memory_summary.csv` report complete
worker peak host RSS and sampled CUDA memory increases with denominators.
They include data loading and quality assessment, not only the timed fit.
Captions identify the campaign and read its
`final_audit.txt`: absent or failed audits label all outputs diagnostic.

The JSS PDF is compiled from the LaTeX manuscript after those files are
generated. For editable Word output, `prepare_jss_docx_source.R` expands the
generated LaTeX and substitutes PNG runtime figures, then
`format_jss_docx.py` formats author superscripts and the wide table:

```bash
Rscript analysis/prepare_jss_docx_source.R INPUT.tex /tmp/jss_word.tex
pandoc -f latex -t docx /tmp/jss_word.tex \
  --resource-path=/absolute/path/to/manuscript/jss \
  --bibliography=/absolute/path/to/manuscript/jss/fastEmbedR_JSS.bib \
  --citeproc -o /tmp/jss_word_raw.docx
python3 analysis/format_jss_docx.py \
  /tmp/jss_word_raw.docx /absolute/path/to/output.docx
```

For the supplement, Pandoc does not preserve the LaTeX `longtable` as an
editable table. After formatting its DOCX, insert the same generated
runtime values as a native Word table:

```bash
python3 analysis/add_runtime_table_to_supp_docx.py \
  /absolute/path/to/supplement.docx \
  /absolute/path/to/generated/table_all_methods_runtime_supp.csv \
  CAMPAIGN_ID /absolute/path/to/supplement_with_table.docx
```

```bash
make tables
make figures
make validate
```

The validation step checks required columns, non-negative finite runtimes,
timing-scope separation, output presence, and checksum coverage.

For the secondary JSS comparisons, use one copied 2D campaign and, when
available, its separately audited 3D lane:

```bash
Rscript analysis/build_secondary_comparisons.R \
  /absolute/path/to/2d-campaign/results \
  /absolute/path/to/manuscript/generated/secondary \
  /absolute/path/to/3d-lane
```

The archived September 30 campaign predates the expanded stage schema
required by `build_secondary_comparisons.R`. Its published scaling, landmark,
and clustering TeX tables are rendered from the compact CSVs bundled in
`manuscript/jss/generated/secondary_20260930/` by
`render_jss_secondary_20260930.R`, which the manuscript build invokes.

The script writes dataset-level and summary CSVs for CPU thread scaling,
20-percent landmarks, and clustering, along with a paired 2D/3D status and
runtime-memory-quality table. Landmark RSS and incremental GPU-memory ratios
come from isolated full and landmark processes when those results exist.
CPU scaling outputs include KNN, rank-2 and rank-up-to-50 PCA, SNN graph
construction, prepared-KNN graph-plus-clustering fits, t-SNE, and UMAP at
1, 2, 4, 8, and 12 workers. The full stage CSV retains serial fit-only
timings. Stage-specific observation counts prevent comparing full-input
embedding runs with bounded clustering or rank-50 PCA as if they used the
same matrix.
The 3D table also records sampled KL for t-SNE
and rejects mismatched seeds, row counts, dimensions, or timing boundaries.
Missing 3D runs remain `not_run`; absent landmark peak-memory ratios remain
empty. The CPU, landmark, and clustering LaTeX snippets and two figures are
generated from the same input campaign. A 3D summary table and plot are
generated only when at least one valid paired result exists.
When a 3D lane is supplied, its same-image 2D baselines are mandatory;
the older campaign contributes only the scaling, landmark, and clustering
summaries.
