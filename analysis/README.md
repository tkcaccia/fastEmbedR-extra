# Analysis workflow

The analysis has two stages.

1. `aggregate_linux_results.R` and `aggregate_macos_results.R` read local raw
   result archives and write compact CSV summaries.
2. `build_tables.R` and `build_figures.R` use only those aggregate CSV files.

This separation allows all publication tables and figures to be rebuilt
without distributing restricted datasets or multi-gigabyte worker outputs.

The JSS campaign writes an `embedding.csv` for each successful PCA, t-SNE,
and UMAP method. Build its runtime table, t-SNE and UMAP runtime figures,
and method gallery from one campaign only:

```bash
Rscript analysis/build_table5_and_embedding_gallery.R \
  /absolute/path/to/campaign/results \
  /absolute/path/to/output/generated \
  /absolute/path/to/output/figures/embedding_all_methods \
  figures/embedding_all_methods
```

The second and third paths are output directories. The fourth argument is the
figure path relative to the LaTeX document. Omit them to write under the
campaign's `results/publication` directory. The builder reads only
`aggregate/workflow_comparators_all.csv` and coordinate CSVs inside the
specified campaign. The table and runtime figures use timing-eligible rows;
missing combinations remain empty or marked unavailable. R total-call and
direct-Python fit times are visually separated and must not be divided to
form speedup claims. Captions identify the campaign and read its
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

```bash
make tables
make figures
make validate
```

The validation step checks required columns, non-negative finite runtimes,
timing-scope separation, output presence, and checksum coverage.
